from openai import OpenAI
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
import json

app = FastAPI()

# Define your OpenAI API key
api_key = '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'

def gpt_sp(json_file: dict, module: str):
    print(json_file)
    print(module)
    try:
        # Define the request payload based on the module
        if module == "simptoms":
            request_content = "Please provide me with a medical recommendation in JSON format."
        elif module == "scannertext":
            request_content = "Could you please analyze the JSON file provided and generate a response based on the specified guidelines?. don't return the same json please"
        else:
            raise ValueError("Invalid module specified")

        # Initialize the OpenAI client
        client = OpenAI(api_key=api_key)

        # Convert the JSON payload to a string
        request_payload_str = json.dumps(json_file)

        # Send the JSON payload to OpenAI
        response = client.chat.completions.create(
            model="gpt-3.5-turbo",
            response_format={"type": "json_object"},
            messages=[{"role": "user", "content": f"{request_content} {request_payload_str}"}]
        )

        # Fetch the result as a JSON string
        json_result = response.choices[0].message.content

        # Parse the JSON string to a Python dictionary
        result = json.loads(json_result)

        print('result test',result)

        return JSONResponse(content=result, status_code=200)

    except Exception as e:
        # If an error occurs, return an HTTP 500 error with the error message
        raise HTTPException(status_code=500, detail=str(e))