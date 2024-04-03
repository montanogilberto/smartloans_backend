from azure.cognitiveservices.vision.computervision import ComputerVisionClient
from azure.cognitiveservices.vision.computervision.models import OperationStatusCodes
from msrest.authentication import CognitiveServicesCredentials
import time
import io
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
import json

app = FastAPI()

subscription_key = "56dbb0a7600b46bc946765d4b02cb5a2"
endpoint = "https://testcomputervisionv2.cognitiveservices.azure.com/"

text_lines = []

def scannertext_sp(json_file: dict):

    try:

        computervision_client = ComputerVisionClient(endpoint, CognitiveServicesCredentials(subscription_key))

        #read_image_url = "https://learn.microsoft.com/azure/ai-services/computer-vision/media/quickstarts/presentation.png"

        # Path to the local image file
        image_path = "/Users/apple12/PycharmProjects/pythonProject/smartloans_backend/files/test/exaliv.jpeg"

        # Read the image file in binary mode
        with open(image_path, "rb") as image_file:
            image_data = image_file.read()

        # Create a streamable object from the image data
        image_stream = io.BytesIO(image_data)

        # Call API with image stream and raw response (allows you to get the operation location)
        read_response = computervision_client.read_in_stream(image_stream,  raw=True)

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

        # Iterate through the detected text lines and add them to the dictionary
        if read_result.status == OperationStatusCodes.succeeded:
            for text_result in read_result.analyze_result.read_results:
                for line in text_result.lines:
                    # Add the text line to the list
                    text_lines.append({
                        'text': line.text,
                        'bounding_box': line.bounding_box
                    })

        # Convert the dictionary to JSON format
        output_json = json.dumps(text_lines, indent=4)

        # Write the JSON data to a file
        output_file_path = 'output.json'
        with open(output_file_path, 'w') as output_file:
            output_file.write(output_json)

        # Read the JSON file and print its contents
        with open(output_file_path, 'r') as output_file:
            print(output_file.read())

        return JSONResponse(content=output_file, status_code=200)

    except Exception as e:
        # If an error occurs, return an HTTP 500 error with the error message
        raise HTTPException(status_code=500, detail=str(e))