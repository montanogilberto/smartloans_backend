import requests

# Replace 'your_subscription_key' with your actual subscription key
subscription_key = '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'
endpoint = 'https://westus.api.cognitive.microsoft.com/vision/v3.1/ocr'

# Provide the path to the image you want to analyze
image_path = '../files/test/exaliv.jpeg'
image_data = open(image_path, 'rb').read()

headers = {'Ocp-Apim-Subscription-Key': subscription_key,
           'Content-Type': 'application/octet-stream'}

params = {'language': 'en', 'detectOrientation': 'true'}

response = requests.post(endpoint, headers=headers, params=params, data=image_data)
response.raise_for_status()

# Extract text from response
extracted_text = ''
for region in response.json()['regions']:
    for line in region['lines']:
        for word in line['words']:
            extracted_text += word['text'] + ' '

print(extracted_text)
