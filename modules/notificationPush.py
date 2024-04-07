from azure.notificationhubs import NotificationHubClient

hub_connection_string = "Endpoint=sb://Pharmacypush2.servicebus.windows.net/;SharedAccessKeyName=DefaultFullSharedAccessSignature;SharedAccessKey=1beS4Hry9bqfZTu+98QZ3iW0hiG4ZV48kegERGw8tQw="
hub_name = "Trst"
notification_hub_client = NotificationHubClient(hub_connection_string, hub_name)

def register_device(device_token):
    try:
        notification_hub_client.create_or_update_registration({
            "registrationId": device_token,
            "deviceToken": device_token,
            "tags": ["your_tag"]
        })
        print("Device registration successful.")
    except Exception as e:
        print("Device registration failed:", e)

# Example usage:
device_token = "<your_device_token>"
register_device(device_token)
