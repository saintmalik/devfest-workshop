import logging
import time
import os
import csv
from datetime import datetime
from flask import Flask, request, g
from pythonjsonlogger import jsonlogger
from prometheus_flask_exporter import PrometheusMetrics
from opentelemetry.instrumentation.flask import FlaskInstrumentor

from .config import app_config
from .models import db
from .views.people import people_api as people

logger = logging.getLogger("wide_event")


def create_app(env_name: str) -> Flask:
    """
    Initializes the application with Observability
    """
    app = Flask(__name__)
    app.config.from_object(app_config[env_name])

    log_level = logging.INFO
    if env_name == "production":
        handler = logging.StreamHandler()
        formatter = jsonlogger.JsonFormatter(
            fmt="%(asctime)s %(levelname)s %(name)s %(message)s"
        )
        handler.setFormatter(formatter)

        # Configure root logger
        root = logging.getLogger()
        root.handlers = []
        root.addHandler(handler)
        root.setLevel(log_level)

        # Configure wide_event logger
        logger.handlers = []
        logger.addHandler(handler)
        logger.propagate = False  # Don't bubble up to root to avoid double logs
        logger.setLevel(log_level)

        # Suppress noisy standard logs in prod
        logging.getLogger("werkzeug").setLevel(logging.ERROR)
        app.logger.handlers = []
        app.logger.addHandler(handler)

        logger.info(
            "Application starting", extra={"env": env_name, "mode": "production"}
        )
    else:
        # Development: Human-readable terminal logs
        handler = logging.StreamHandler()
        formatter = logging.Formatter(
            "[%(asctime)s] %(levelname)s in %(module)s: %(message)s"
        )
        handler.setFormatter(formatter)

        root = logging.getLogger()
        root.handlers = []
        root.addHandler(handler)
        root.setLevel(log_level)

        # Configure wide_event logger
        logger.handlers = []
        logger.addHandler(handler)
        logger.propagate = False
        logger.setLevel(log_level)

        # In dev, keep Werkzeug logs visible
        logging.getLogger("werkzeug").setLevel(logging.INFO)
        app.logger.handlers = []
        app.logger.addHandler(handler)

        logger.info(f"Application starting in {env_name} mode")

    # 0. IAM Auth (RDS)
    from .db_auth import configure_sqlalchemy_iam_auth

    configure_sqlalchemy_iam_auth(app)

    # 1. Database
    db.init_app(app)

    # 2. Metrics (Prometheus)
    metrics = None
    if app.config.get("ENABLE_METRICS"):
        metrics = PrometheusMetrics(app)
        # static labels can be added here if needed
        metrics.info("app_info", "Application info", version="1.0.0", env=env_name)

    # 3. Tracing (OpenTelemetry)
    # Note: Full OTel setup usually requires the OTel distro run command or further config
    # This hooks Flask into the OTel API
    if app.config.get("ENABLE_TRACING"):
        FlaskInstrumentor().instrument_app(app)

    # 4. Wide Events Middleware (Structured Logging)
    @app.before_request
    def start_timer():
        g.start = time.time()

    @app.after_request
    def log_request(response):
        if request.path == "/health" or request.path == "/metrics":
            return response

        diff = time.time() - getattr(g, "start", time.time())

        # Structured log entry (Wide Event)
        log_data = {
            "method": request.method,
            "path": request.path,
            "status": response.status_code,
            "duration_ms": int(diff * 1000),
            "ip": request.remote_addr,
            "user_agent": request.headers.get("User-Agent"),
            "env": env_name,
        }

        # Use our logger - if prod, this will be JSON
        logger.info("request_completed", extra=log_data)

        return response

    # 5. Database Initialization & Seeding
    def initialize_database():
        with app.app_context():
            # Create tables (idempotent)
            db.create_all()

            # Seed from CSV if empty
            from .models.person import Person

            if Person.query.first() is None:
                csv_path = os.path.join(app.root_path, "..", "titanic.csv")
                if os.path.exists(csv_path):
                    app.logger.info(f"Seeding database from {csv_path}...")
                    try:
                        with open(csv_path, "r", encoding="utf-8") as f:
                            reader = csv.DictReader(f)
                            for row in reader:
                                person_data = {
                                    "survived": int(row["Survived"]),
                                    "passengerClass": int(row["Pclass"]),
                                    "name": row["Name"],
                                    "sex": row["Sex"],
                                    "age": float(row["Age"]),
                                    "siblingsOrSpousesAboard": int(
                                        row["Siblings/Spouses Aboard"]
                                    ),
                                    "parentsOrChildrenAboard": int(
                                        row["Parents/Children Aboard"]
                                    ),
                                    "fare": float(row["Fare"]),
                                }
                                person = Person(person_data)
                                db.session.add(person)
                        db.session.commit()
                        app.logger.info("Successfully seeded database.")
                    except Exception as e:
                        db.session.rollback()
                        app.logger.error(f"Failed to seed database: {e}")

    initialize_database()

    # 6. Register Blueprints
    app.register_blueprint(people, url_prefix="/")

    @app.route("/", methods=["GET"])
    def index():
        """Root endpoint"""
        return "Welcome to the Titanic API"

    @app.route("/health", methods=["GET"])
    def health():
        """Lightweight health check endpoint"""
        return {"status": "healthy"}, 200

    # Conditionally exclude health check from metrics
    if metrics:
        metrics.do_not_track()(health)

    return app
