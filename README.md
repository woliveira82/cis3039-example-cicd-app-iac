# Frontend App CI/CD Example

## CI/CD Features

This project includes a GitHub Actions workflow (`.github/workflows/build.yml`) to build the project. This would act as a Continuous Integration (CI) check to verify the latest code changes (git commit) have not broken the code base.

The same workflow also validates the Terraform code in `infra/` and, on pushes to `main`, deploys the app to Azure with Terraform (see [Deploy from GitHub Actions](#deploy-from-github-actions)).

Make a small code change, `git commit`, `git push` and then observe the GitHub Action running in the GitHub website (within the Actions tab of the code repo).

> There may be other branches in this repo demonstrating additional CI/CD features.

### Configuring CI/CD

Single Page Apps (SPAs) must bake env vars in at build time. This means they must be built to target a specific environment and must be rebuilt for different environments. The only env var in this base project is `VITE_API_BASE_URL` which must be set to point at the backend products web service. For the CI build check, this env var is set in the workflow file; the deploy job builds with the real API URL from Terraform (`api_base_url`).

## Local Setup

### Install dependencies

```bash
npm install
```

### Configure local environment variables

```bash
cp .env.example .env.local
```

Update/add values within `.env.local`

> Note: Never commit your `.env.local` to source control. The example is safe to share.

### Compile and Hot-Reload for Development

```bash
npm run dev
```

### Type-Check, Compile and Minify for Production

```bash
npm run build
```

## Azure Setup

The `infra/` folder holds Terraform that creates everything below and publishes the app. It can be run locally or by the GitHub Actions `deploy` job. The [manual steps](#manual-setup-with-the-azure-cli) further down do the same thing by hand.

| Purpose | Implemented by |
| --- | --- |
| Resource group | `azurerm_resource_group.this` |
| Storage account for the SPA | `azurerm_storage_account.web` |
| Static website hosting | `azurerm_storage_account_static_website.web` |
| CORS on the Function App | `terraform_data.function_app_cors` (runs `az functionapp cors`) |
| Build and publish the SPA | `terraform_data.publish_app` (runs `npm` and `az storage blob upload-batch`) |

### Deploy with Terraform (local)

Requires Terraform, the Azure CLI (logged in with `az login`), Node.js and bash.

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # set the 3 required values
terraform init
terraform apply
```

Only `subscription_id`, `function_app_name` and `function_app_resource_group_name` are required; `project`, `environment`, `location` and `api_base_url` have defaults.

### Deploy from GitHub Actions

The `deploy` job in `.github/workflows/build.yml` runs `terraform apply` on every push to `main`, after the app build and `terraform validate` pass. It logs in to Azure with OIDC (no stored password) and keeps state in an Azure Storage container, so the generated names stay the same between runs.

One-time setup:

1. **State storage.** Create a storage account and container for Terraform state (outside this configuration, so `terraform destroy` can't delete it):

   ```bash
   az group create --name <tfstate-rg> --location uksouth
   az storage account create --name <tfstatestorage> --resource-group <tfstate-rg> \
     --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2
   az storage container create --name tfstate --account-name <tfstatestorage> --auth-mode login
   ```

2. **Identity for GitHub.** Create an app registration with a federated credential for this repo's `production` environment, and give it **Contributor** on the subscription (it creates the resource group, updates the Function App's CORS and reads the storage account keys):

   ```bash
   APP_ID=$(az ad app create --display-name products-app-github --query appId -o tsv)
   az ad sp create --id $APP_ID
   az ad app federated-credential create --id $APP_ID --parameters '{
     "name": "github-production",
     "issuer": "https://token.actions.githubusercontent.com",
     "subject": "repo:<owner>/<repo>:environment:production",
     "audiences": ["api://AzureADTokenExchange"]
   }'
   az role assignment create --assignee $APP_ID --role Contributor \
     --scope /subscriptions/<subscription-id>
   ```

3. **GitHub settings** (Settings → Environments → `production`):

   | Type | Name | Value |
   | --- | --- | --- |
   | Secret | `AZURE_CLIENT_ID` | `$APP_ID` from step 2 |
   | Secret | `AZURE_TENANT_ID` | `az account show --query tenantId -o tsv` |
   | Secret | `AZURE_SUBSCRIPTION_ID` | `az account show --query id -o tsv` |
   | Variable | `FUNCTION_APP_NAME` | Existing backend Function App |
   | Variable | `FUNCTION_APP_RESOURCE_GROUP` | Its resource group |
   | Variable | `TFSTATE_RESOURCE_GROUP` | `<tfstate-rg>` |
   | Variable | `TFSTATE_STORAGE_ACCOUNT` | `<tfstatestorage>` |
   | Variable | `TFSTATE_CONTAINER` | Optional, defaults to `tfstate` |
   | Variable | `API_BASE_URL` | Optional, see `api_base_url` |

The workflow adds the remote backend at run time by writing `infra/backend_override.tf` (git-ignored), so local runs keep using local state. Local state and CI state are separate: a local `terraform apply` creates its own set of resources.

### Resource names

Names are generated as `<project>-<environment>-<suffix>-<type>`. The suffix is six random characters, stored in state so it stays the same across applies.

| Resource | Example name |
| --- | --- |
| Resource group | `products-lab-x7k2qm-rg` |
| Storage account (letters and digits only) | `productslabx7k2qmst` |

`project` is limited to 10 characters and `environment` to 6, which keeps the storage account name within Azure's 24-character limit.

### Terraform notes

- **State** contains secrets, such as the storage account keys. Locally it is stored in `infra/terraform.tfstate`, which is git-ignored, so don't commit it. CI uses the remote state described above.
- **Removed files stay published.** Publishing overwrites blobs but doesn't delete old ones, so old hashed assets remain in `$web`.
- **The Function App is deployed separately**, so its name isn't generated. Terraform only adds the site to its CORS list.
- **Changes made outside Terraform** to the Function App's CORS list aren't detected, because it is only updated when the origin or Function App changes.

### Manual setup with the Azure CLI

#### Publish the app to an Azure Storage Account (static website)

1. Create a Storage Account suited for static sites:

```bash
az storage account create \
  --name <productappstoragename> \
  --resource-group <your-resource-group> \
  --location <permitted-location> \
  --sku Standard_LRS \
  --kind StorageV2
```

2. Enable static website and set the index page:

```bash
az storage blob service-properties update \
  --account-name <productappstoragename> \
  --static-website \
  --index-document index.html \
  --404-document index.html
```

3. Build the SPA and upload the contents of dist to the `$web` container:

```bash
# build
npm run build

# publish
az storage blob upload-batch \
  --account-name <productappstoragename> \
  --source ./dist \
  --destination '$web' \
  --overwrite

# get URL
az storage account show \
  --name <productappstoragename> \
  --resource-group <your-resource-group> \
  --query "primaryEndpoints.web" \
  --output tsv
```

4. Add your storage site to CORS on the Function App (so the deployed web app can access the web service):

```bash
az functionapp cors add \
  --name <your-backend-products-func> \
  --resource-group <your-resource-group> \
  --allowed-origins https://<app-store-endpoint>
```

## How the project was made

This section explains how you could create a new project in the same style as this one.

Initialise the project files:

```bash
npm create vue@3 . -- \
  --force \
  --bare \
  --typescript \
  --router \
  --prettier
```

Restore any delete devcontainer configuration:

```bash
git restore .devcontainer/devcontainer.json
```

Add extensions to devcontainer:

- `"esbenp.prettier-vscode"`,
- `"Vue.volar"`

Update preferences in `.prettierrc.json`:

- `"semi": true`
- `"singleQuote": true`
- `"printWidth": 80`
