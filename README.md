# Frontend App CI/CD Example

## CI/CD Features

This project includes a GitHub Actions workflow (`.github/workflows/build.yml`) to build the project. This would act as a Continuous Integration (CI) check to verify the latest code changes (git commit) have not broken the code base.

The same workflow also validates the Terraform code in `infra/`, plans infrastructure changes on pull requests to `main` and, on pushes to `main`, deploys the app to Azure with Terraform (see [CI/CD workflow](#cicd-workflow)).

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

The `infra/` folder holds Terraform that creates everything below and publishes the app. It can be run locally or by the GitHub Actions `deploy` job, and both share the same remote state. The [manual steps](#manual-setup-with-the-azure-cli) further down do the same thing by hand.

| Purpose | Implemented by |
| --- | --- |
| Resource group | `azurerm_resource_group.this` |
| Storage account for the SPA | `azurerm_storage_account.web` |
| Static website hosting | `azurerm_storage_account_static_website.web` |
| CORS on the Function App | `terraform_data.function_app_cors` (runs `az functionapp cors`) |
| Build and publish the SPA | `terraform_data.publish_app` (runs `npm` and `az storage blob upload-batch`) |

### CI/CD workflow

The workflow `.github/workflows/build.yml` runs:

| Event | Jobs |
| --- | --- |
| Push / pull request to `main` or `develop` | `build` (type check, npm build, `terraform fmt`/`validate`) |
| Pull request to `main` | `build` then `plan` (Terraform plan against Azure) |
| Push to `main` / manual run on `main` | `build` then `deploy` (Terraform apply, which builds and publishes the SPA and sets CORS, then a smoke test of the website) |

### One-time setup

Terraform state must be stored in Azure so CI runs (and your local runs) share it. GitHub signs in to Azure as a service principal using a client secret, stored as the secret `AZURE_CLIENT_SECRET`. The secret expires (1 year below), so rotate it before then (see [Rotating the client secret](#rotating-the-client-secret)).

1. Create the Terraform state storage (pick a globally unique account name):

```bash
LOCATION=uksouth
TFSTATE_RG=products-lab-tfstate-rg
TFSTATE_SA=<yourtfstateaccount>

az group create --name $TFSTATE_RG --location $LOCATION
az storage account create --name $TFSTATE_SA --resource-group $TFSTATE_RG \
  --location $LOCATION --sku Standard_LRS \
  --min-tls-version TLS1_2 --allow-blob-public-access false
az storage container-rm create --storage-account $TFSTATE_SA \
  --resource-group $TFSTATE_RG --name tfstate
```

2. Create an identity for GitHub Actions and a client secret for it:

```bash
SUB_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
APP_ID=$(az ad app create --display-name products-lab-cicd --query appId -o tsv)
az ad sp create --id $APP_ID

CLIENT_SECRET=$(az ad app credential reset --id $APP_ID --append \
  --display-name github-actions --years 1 --query password -o tsv)
```

> Treat `CLIENT_SECRET` like a password: don't echo it, commit it or paste it anywhere except the GitHub secret below.

3. Grant access: the identity creates resources in the subscription, updates the Function App's CORS, reads the website storage account keys (to upload the SPA) and reads/writes the state blob. You also need blob access to run Terraform locally.

```bash
TFSTATE_ID=$(az storage account show --name $TFSTATE_SA --resource-group $TFSTATE_RG --query id -o tsv)

az role assignment create --assignee $APP_ID --role Contributor --scope /subscriptions/$SUB_ID
az role assignment create --assignee $APP_ID --role "Storage Blob Data Contributor" --scope $TFSTATE_ID
az role assignment create --assignee $(az ad signed-in-user show --query id -o tsv) \
  --role "Storage Blob Data Contributor" --scope $TFSTATE_ID
```

4. Create a `dev` environment in the GitHub repo (Settings > Environments), then add the secret and variables to it (the client secret goes under **Secrets**, the rest under **Variables**), or with the `gh` CLI:

```bash
gh secret set AZURE_CLIENT_SECRET --env dev --body "$CLIENT_SECRET"
gh variable set AZURE_CLIENT_ID --env dev --body $APP_ID
gh variable set AZURE_TENANT_ID --env dev --body $TENANT_ID
gh variable set AZURE_SUBSCRIPTION_ID --env dev --body $SUB_ID
gh variable set TFSTATE_RESOURCE_GROUP --env dev --body $TFSTATE_RG
gh variable set TFSTATE_STORAGE_ACCOUNT --env dev --body $TFSTATE_SA
gh variable set AZURE_LOCATION --env dev --body $LOCATION
gh variable set FUNCTION_APP_NAME --env dev --body <your-backend-products-func>
gh variable set FUNCTION_APP_RESOURCE_GROUP --env dev --body <its-resource-group>
# Optional: TFSTATE_CONTAINER (default tfstate), API_BASE_URL (see api_base_url)
```

### Rotating the client secret

Before the secret expires (or if it leaks), create a new one and update GitHub. `--append` keeps the old one working until you remove it:

```bash
CLIENT_SECRET=$(az ad app credential reset --id $APP_ID --append \
  --display-name github-actions --years 1 --query password -o tsv)
gh secret set AZURE_CLIENT_SECRET --env dev --body "$CLIENT_SECRET"

# Then remove the old one (find its keyId in the list):
az ad app credential list --id $APP_ID -o table
az ad app credential delete --id $APP_ID --key-id <old-key-id>
```

### Running Terraform locally

Requires Terraform, the Azure CLI (signed in with `az login`), Node.js and bash. Local runs use the same remote state as CI, so they manage the same resources.

```bash
cd infra
cp backend.hcl.example backend.hcl             # fill in the same TFSTATE values
cp terraform.tfvars.example terraform.tfvars   # set the 2 required values
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

Only `function_app_name` and `function_app_resource_group_name` are required; `subscription_id` (current `az` subscription), `project`, `environment`, `location` and `api_base_url` have defaults.

> If you previously applied with local state, run `terraform init -migrate-state -backend-config=backend.hcl` to move it into Azure instead of creating a second set of resources.

### Resource names

Names are generated as `<project>-<environment>-<suffix>-<type>`. The suffix is six random characters, stored in state so it stays the same across applies.

| Resource | Example name |
| --- | --- |
| Resource group | `products-lab-x7k2qm-rg` |
| Storage account (letters and digits only) | `productslabx7k2qmst` |

`project` is limited to 10 characters and `environment` to 6, which keeps the storage account name within Azure's 24-character limit.

### Terraform notes

- **State** is stored in the Azure Storage container from the one-time setup and contains secrets, such as the storage account keys. Limit who has access to that storage account.
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
