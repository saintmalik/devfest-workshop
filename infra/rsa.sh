SUBSCRIPTION="514ca6ed-1be2-4ae4-86d5-175a0ad4fb87"

# Get your user object ID
MY_OID=$(az ad signed-in-user show --query id -o tsv)
echo "Your OID: $MY_OID"

# Assign Key Vault Crypto Officer role
az role assignment create \
  --role "Key Vault Crypto Officer" \
  --assignee "$MY_OID" \
  --scope "/subscriptions/$SUBSCRIPTION/resourceGroups/tfstate-rg/providers/Microsoft.KeyVault/vaults/saintmalikinfra-vault"

# Now create the key
az keyvault key create \
  --vault-name "saintmalikinfra-vault" \
  --name "tofu-state-key" \
  --kty RSA \
  --size 2048