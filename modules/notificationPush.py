from azure.identity import DefaultAzureCredential
from azure.mgmt.notificationhubs import NotificationHubsManagementClient

credential = DefaultAzureCredential()

# Provide your Azure Subscription ID and Resource Group Name
subscription_id = '<your_subscription_id>'
resource_group_name = '<your_resource_group_name>'

# Provide your Azure Notification Hub Namespace Name and Notification Hub Name
namespace_name = '<your_notification_hub_namespace_name>'
notification_hub_name = '<your_notification_hub_name>'

# Initialize the Notification Hubs Management Client
notification_hubs_client = NotificationHubsManagementClient(credential, subscription_id)

# Get the shared access policy primary key
keys = notification_hubs_client.namespaces.list_keys(resource_group_name, namespace_name)
shared_access_key = keys.primary_key

# Construct the connection string
hub_connection_string = f'Endpoint=sb://{namespace_name}.servicebus.windows.net/;SharedAccessKeyName=DefaultFullSharedAccessSignature;SharedAccessKey={shared_access_key}'

def register_device(device_token):
    try:
        notification_hubs_client.registrations.create_or_update(
            resource_group_name,
            namespace_name,
            notification_hub_name,
            device_token,
            {"deviceToken": device_token, "tags": ["your_tag"]}
        )
        print("Device registration successful.")
    except Exception as e:
        print("Device registration failed:", e)

# Example usage:
device_token = "<your_device_token>"
register_device(device_token)
