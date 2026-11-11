# Infrastructure

Terraform for the app's Azure resources. For background, see [Azure Setup](../README.md#azure-setup) in the project README.

| Purpose | Implemented by |
| --- | --- |
| Resource group | `azurerm_resource_group.this` |
| Storage account for the SPA | `azurerm_storage_account.web` |
| Static website hosting | `azurerm_storage_account_static_website.web` |
| CORS on the Function App | `terraform_data.function_app_cors` (runs `az functionapp cors`) |
| Build and publish the SPA | `terraform_data.publish_app` (runs `npm` and `az storage blob upload-batch`) |

## Deploy

Requires Terraform, the Azure CLI (logged in with `az login`), Node.js and bash.

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # set the 3 required values
terraform init
terraform apply
```

Only `subscription_id`, `function_app_name` and `function_app_resource_group_name` are required; `project`, `environment`, `location` and `api_base_url` have defaults.

## Resource names

Names are generated as `<project>-<environment>-<suffix>-<type>`. The suffix is six random characters, stored in state so it stays the same across applies.

| Resource | Example name |
| --- | --- |
| Resource group | `products-lab-x7k2qm-rg` |
| Storage account (letters and digits only) | `productslabx7k2qmst` |

`project` is limited to 10 characters and `environment` to 6, which keeps the storage account name within Azure's 24-character limit.

## Notes

- **State** is stored locally in `infra/terraform.tfstate` and contains secrets, such as the storage account keys. It is git-ignored, so don't commit it. Configure a remote backend if more than one person deploys this.
- **Removed files stay published.** Publishing overwrites blobs but doesn't delete old ones, so old hashed assets remain in `$web`.
- **The Function App is deployed separately**, so its name isn't generated. Terraform only adds the site to its CORS list.
- **Changes made outside Terraform** to the Function App's CORS list aren't detected, because it is only updated when the origin or Function App changes.
