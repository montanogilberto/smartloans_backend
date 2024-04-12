from azure.cognitiveservices.vision.computervision import ComputerVisionClient
from azure.cognitiveservices.vision.computervision.models import OperationStatusCodes
from msrest.authentication import CognitiveServicesCredentials
import time
import io
import requests
from fastapi import FastAPI, HTTPException, Response
from fastapi.responses import JSONResponse
from modules.api_gpt import gpt_sp

app = FastAPI()

subscription_key = "c402a7afc8264763aa5f40efe04c79df"
endpoint = "https://pharmacyappv2.cognitiveservices.azure.com/"

def process_image_url(image_url: str) -> list:
    print(image_url)
    try:
        computervision_client = ComputerVisionClient(endpoint, CognitiveServicesCredentials(subscription_key))

        # Read the image file from the URL
        image_data = requests.get(image_url).content

        # Create a streamable object from the image data
        image_stream = io.BytesIO(image_data)

        # Call API with image stream and raw response (allows you to get the operation location)
        read_response = computervision_client.read_in_stream(image_stream, raw=True)

        # Get the operation location (URL with an ID at the end) from the response
        read_operation_location = read_response.headers["Operation-Location"]

        # Grab the ID from the URL
        operation_id = read_operation_location.split("/")[-1]

        # Call the "GET" API and wait for it to retrieve the results
        while True:
            read_result = computervision_client.get_read_result(operation_id)
            if read_result.status not in ['notStarted', 'running']:
                break
            time.sleep(1)

        # Iterate through the detected text lines and add them to the list
        text_lines = []
        if read_result.status == OperationStatusCodes.succeeded:
            for text_result in read_result.analyze_result.read_results:
                for line in text_result.lines:
                    text_lines.append(line.text)

        print('text_lines',text_lines)
        return text_lines

    except Exception as e:
        # If an error occurs, raise it
        print("An error occurred:", e)
        raise e

def generate_json_output(results):
    result_json = {
        "json_products": [
            {
                "description": "Could you assist me in analyzing the text content within each 'text_lines' node corresponding to every 'image' element? I need a comprehensive analysis with clear descriptions, utilizing logic and context to extract relevant information. Please present the analysis in Spanish and ensure that any unrecognized words are contextualized. Additionally, format the response using the specified node structure.",
                "format": {
                    "Product Name": "",
                    "Intended Use(symptoms)": [],
                    "Active Ingredients": "[[name:'',dosage:'']]",  # Placeholder for active ingredients
                    "Packaging": "",
                    "Route of Administration": "",
                    "expiration_date":"",
                    "barcode":"",
                    "restrictions":""
                }
            },
            {
                "image": "",  # Assuming this is the image identifier
                "text_lines": results[0]  # Assuming results is a list containing the text lines
            }
        ]
    }

    # Print the JSON output
    print(result_json)

    return result_json


def scannertext_sp(json_file: dict) -> JSONResponse:
    try:
        results = []

        # Iterate over each image in the JSON input
        for img in json_file['images']:
            url_file = img['url_file']
            text_lines = process_image_url(url_file)
            results.append(text_lines)

        # Generate JSON response
        response_json = generate_json_output(results)

        return gpt_sp(response_json, 'scannertext')

    except Exception as e:
        # If an error occurs, return an HTTP 500 error with the error message
        raise HTTPException(status_code=500, detail=str(e))


def process_json(response: Response, json_file: dict):
    try:
        # Process JSON file
        response_data = scannertext_sp(json_file)
        print(response_data)

        # Return JSON response
        return response_data

    except Exception as e:
        # Return error response
        response.status_code = 500
        return {"error": str(e)}

'''
json_data = {
    "images": [
        {
            "image": "image1_20240402",
            "url_file": "https://pharmacyapp.blob.core.windows.net/pharmacy/products/exaliv.jpeg"
        }
    ]
}

scannertext_sp(json_data)
'''