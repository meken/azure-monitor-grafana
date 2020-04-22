# Azure Monitor & Stateless Grafana

[Grafana](https://grafana.com/) is a popular tool for operational monitoring. It has an extensive graphical
UI to create dashboards. It has a flexible plugin ecosystem and can visualize data from various data sources,
including Azure Monitor. If you're monitoring your workloads on Azure, you can access operational data through different methods. This repository is an example of how to visualize different types of monitoring data from
Azure using Grafana in a stateless fashion with provisioned dashboards and datasources. The advantage of this
approach is that you can access your Grafana dashboards through Docker containers even on your local machine,
and if you shut it down and restart you'd still have access to the same data and dashboards. This also makes
GitOps possible by putting the dashboard configurations under version control.

Before we dive into the details of how to turn on this capability, please keep in mind that there's a number of
different ways of accessing monitoring data on Azure. The Azure Monitor data platform is based on two fundamental
datatypes: Metrics and Logs. Please have a look at the
[Azure Monitor](https://docs.microsoft.com/en-us/azure/azure-monitor/platform/data-platform) docs to understand
the differences between those two concepts. In addition, for monitoring applications, there's also the
[Azure Application Insights](https://docs.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview)
option. Luckily, the
[Azure Monitor Datasource](https://grafana.com/docs/grafana/latest/features/datasources/azuremonitor/)
plugin for Grafana supports monitoring through all of those methods. There are 3 dashboards included in the
```sample-dashboards``` directory, one for each of the options. Note that the samples depend on the existence
of certain resource types; the Metrics one looks for Azure SQL Databases, the Log Analytics one is built
for containers (AKS) and the Application Insights dashboard expects at least one instrumented application.

## Prepare the access keys

In order to configure the Azure Monitor Datasource, we need to pass some information about the subscription that
holds the monitoring data.

> Note that these ```az cli``` commands assumes that you've already selected the proper account in
> case you have access to multiple accounts

```bash
TENANT_ID=`az account show --query tenantId -o tsv`
SUBSCRIPTION_ID=`az account show --query id -o tsv`
```

Next step is to create a service principal that has access to the monitoring data. If you've already
created one or you want to alter an existing one, you can skip this step.

```bash
ID_NAME="http://spn-grafana-stateless"  # needs to be a URI
CLIENT_SECRET=`az ad sp create-for-rbac --name $ID_NAME --skip-assignment --query password -o tsv`
CLIENT_ID=`az ad sp show --id $ID_NAME --query appId -o tsv`
```

And now we can assign the proper role to this service principal to access the data.

> This example sets the permissions at the resource group level, you could consider broadening
> the scope to the subscription or narrow it down to a specific resource.

```bash
RG=...  # the resource group that contains the resources to be monitored
SCOPE=`az group show -g $RG --query id -o tsv`
# Now the you can assign the service principal the required role
az role assignment create --assignee $CLIENT_ID --role "Monitoring Reader" --scope $SCOPE
```

### (Optional) Log Analytics

The above instructions enable reading the Azure Monitor metrics. If you'd like to access metrics through Log Analytics
workspaces you'll need to configure access to those workspaces. It's possible to use another service principal for this
purpose, but you can also re-use the service principal by adding another role assignment to the existing service
principal.

In the example below the same service principal is used, and assumes that the Log Analytics workspaces are in the
same resource group as the monitored resources. Similar to monitoring through metrics, you might want to change the
scope to subscription or to another resource group that contains Log Analytics workspaces.

```bash
az role assignment create --assignee $CLIENT_ID --role "Log Analytics Reader" --scope $SCOPE
```

> Note that for this example we're assuming that the same service principal is used for both accessing Azure Monitor
> metrics as well as Log Analytics Workspaces. It's possible to indicate that by setting
> ```azureLogAnalyticsSameAs: true``` in the ```datasources.yaml``` file. However, for the sake of clarity and to
> indicate that you can use different credentials, the included configuration uses the same credentials for both
> methods individually.

### (Optional) Application Insights

If you're planning to try out Application Insights support as well, you'll need to configure that. Note that this
is optional, the rest of the dashboards would keep working even if you wouldn't configure this part.

Azure Application Insights works slightly differently. Instead of relying on a service principal, you'll need to
create an __API_KEY__. The ```az cli``` commands for doing that are in preview at the time this writing, so you'll
need to enable it if you haven't done so.

```bash
az extension add -n application-insights
```

Once the extension has been enabled, you can create the api key from the command line with the following commands.

```bash
APP_INSIGHTS_RG=...  # resource group where the specific app insights resource has been created
APP_INSIGHTS_NAME=...  # name of the specific app insights resource
APP_INSIGHTS_ID=`az monitor app-insights component show -g $APP_INSIGHTS_RG -a $APP_INSIGHTS_NAME --query appId -o tsv`
APP_INSIGHTS_KEY=`az monitor app-insights api-key create -g $APP_INSIGHTS_RG -a $APP_INSIGHTS_NAME \
    --api-key Grafana --read-properties ReadTelemetry --query apiKey -o tsv`
 ```

## Build and run the image

The process of building and running the Docker image is pretty straight forward. All you need to do is to pass
the environment variables that have been created in the previous steps to the container.

```bash
IMG_TAG=grafana-azure-monitor:1

docker build -t $IMG_TAG .

docker run -d -p 3000:3000 \
    -e TENANT_ID="$TENANT_ID" \
    -e SUBSCRIPTION_ID="$SUBSCRIPTION_ID" \
    -e CLIENT_ID="$CLIENT_ID" \
    -e CLIENT_SECRET="$CLIENT_SECRET" \
    -e APP_INSIGHTS_ID="$APP_INSIGHTS_ID" \
    -e APP_INSIGHTS_KEY="$APP_INSIGHTS_KEY" \
    $IMG_TAG
```

## Authenticating through Azure AD

The default username/password for Grafana is admin/admin, which you can change after first login. You can also set a
strong password and pass that as an enviroment variable. You can make up a strong password yourself, or use a utility.
The example below uses ```openssl```, but you could use anything you like.

```bash
GRAFANA_ADMIN_PASSWORD=`openssl rand -base64 32`

docker run -d -p 3000:3000 \
    -e GF_SECURITY_ADMIN_PASSWORD="$GRAFANA_ADMIN_PASSWORD" \
    ...  # set other environment variables too
    $IMG_TAG
```

Additionally you can give access to users through Azure AD OAuth. It all starts with having a service principal
configured properly. Please follow the instructions as laid out in the
[Grafana docs](https://grafana.com/docs/grafana/latest/auth/azuread/#azure-ad-oauth2-authentication).

Instead of editing the ```grafana.ini``` you can pass the configuration again as environment variables.

```bash
OAUTH_CLIENT_ID=...  # assuming that this is a different service principal
OAUTH_CLIENT_SECRET=...  # assuming that this is a different service principal
OAUTH_AUTH_URL="https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/authorize"
OAUTH_TOKEN_URL="https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token"

docker run -d -p 3000:3000 \
    -e GF_AUTH_AZUREAD_ENABLED="true" \
    -e GF_AUTH_AZUREAD_CLIENT_ID="$OAUTH_CLIENT_ID" \
    -e GF_AUTH_AZUREAD_CLIENT_SECRET="$OAUTH_CLIENT_SECRET" \
    -e GF_AUTH_AZUREAD_AUTH_URL="$OAUTH_AUTH_URL" \
    -e GF_AUTH_AZUREAD_TOKEN_URL="$OAUTH_TOKEN_URL" \
    ... # set other environment variables too
    $IMG_TAG
```
