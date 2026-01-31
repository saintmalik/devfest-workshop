SUBSCRIPTION="514ca6ed-1be2-4ae4-86d5-175a0ad4fb87"

# 1. Resource group (--output none suppresses output if already exists)
az group create \
  --name "tfstate-rg" \
  --location "eastus2" \
  --subscription "$SUBSCRIPTION" \
  --output none 2>/dev/null || true

# 2. Storage account
az storage account create \
  --name "saintmalikinfra" \
  --resource-group "tfstate-rg" \
  --location "eastus2" \
  --subscription "$SUBSCRIPTION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --allow-blob-public-access false \
  --min-tls-version TLS1_2 \
  --output none 2>/dev/null || true

# 3. Blob versioning + soft delete
az storage account blob-service-properties update \
  --account-name "saintmalikinfra" \
  --resource-group "tfstate-rg" \
  --subscription "$SUBSCRIPTION" \
  --enable-versioning true \
  --delete-retention-days 7 \
  --enable-delete-retention true

# 4. Blob container
az storage container create \
  --name "tfstate" \
  --account-name "saintmalikinfra" \
  --auth-mode login \
  --output none 2>/dev/null || true

# Register the KeyVault namespace
az provider register \
  --namespace "Microsoft.KeyVault" \
  --subscription "$SUBSCRIPTION"

# 5. Key Vault
az keyvault create \
  --name "saintmalikinfra-vault" \
  --resource-group "tfstate-rg" \
  --location "eastus2" \
  --subscription "$SUBSCRIPTION" \
  --retention-days 90 \
  --enable-purge-protection true

# 6. RSA key
az keyvault key create \
  --vault-name "saintmalikinfra-vault" \
  --name "tofu-state-key" \
  --kty RSA \
  --size 2048