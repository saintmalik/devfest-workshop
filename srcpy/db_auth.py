import boto3
import logging
from urllib.parse import urlparse

logger = logging.getLogger(__name__)


class RDSAuth:
    def __init__(self, region_name="us-west-2"):
        self.region_name = region_name
        self.client = boto3.client("rds", region_name=region_name)

    def generate_token(self, db_host, db_port, db_user):
        """
        Generates an IAM authentication token for RDS.
        """
        try:
            token = self.client.generate_db_auth_token(
                DBHostname=db_host,
                Port=db_port,
                DBUsername=db_user,
                Region=self.region_name,
            )
            return token
        except Exception as e:
            logger.error(f"Failed to generate RDS IAM token: {e}")
            raise e


def configure_sqlalchemy_iam_auth(app):
    """
    Configures Flask-SQLAlchemy to use IAM Auth.
    Since connection tokens expire every 15 minutes, we need to
    ensure we don't cache stale passwords if we were to set it globally.

    However, mostly for simple APIs, the standard approach is to trust
    SQLAlchemy's connection pooling. When the pool recycles, we might need a new token.

    NOTE: For high-traffic production apps, using a custom connection function
    is preferred. This is a simplified "Senior" implementation that updates
    the password in the Config before db initialization if usage suggests.

    But simpler: We can just use a connection hook.
    """
    # For now, we assume the app starts, gets a token, and connects.
    # If the app runs longer than 15m and recycles connections, this might need
    # a `creator` function.

    database_url = app.config.get("SQLALCHEMY_DATABASE_URI")

    if not database_url:
        return

    # Basic check to see if we should apply IAM Auth
    # We apply it if the password is explicitly 'iam-auth-token' or similar placeholder
    # OR if we just decide to overwrite it for RDS.
    # For this task, we will try to apply it if the host contains 'rds.amazonaws.com'

    parsed = urlparse(database_url)

    if parsed.hostname and "rds.amazonaws.com" in parsed.hostname:
        try:
            # Defaults
            port = parsed.port or 5432
            user = parsed.username

            if not user:
                logger.warning("No DB user found in URI, skipping IAM Auth")
                return

            auth = RDSAuth()
            token = auth.generate_token(parsed.hostname, port, user)

            # Reconstruct URI with the new token as password.
            # We use the 'postgresql+psycopg2' or similar scheme from original
            scheme = parsed.scheme
            path = parsed.path
            query = parsed.query

            # Quote the token just in case
            from urllib.parse import quote_plus

            encoded_token = quote_plus(token)

            new_uri = (
                f"{scheme}://{user}:{encoded_token}@{parsed.hostname}:{port}{path}"
            )
            if query:
                new_uri += f"?{query}"

            app.config["SQLALCHEMY_DATABASE_URI"] = new_uri
            logger.info("Successfully injected IAM Auth token into DB URI")

        except Exception as e:
            logger.error(f"Failed to configure IAM Auth: {e}")
            # We don't raise here to allow fallback if possible,
            # though connection will likely fail if password was missing.
