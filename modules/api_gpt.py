from openai import OpenAI
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
import json

app = FastAPI()

# Define your OpenAI API key
api_key = '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'


def symptoms_sp(json_file: dict):
    try:
        # Initialize the OpenAI client
        client = OpenAI(api_key=api_key)

        # Convert the JSON payload to a string
        request_payload_str = json.dumps(json_file)

        # Send the JSON payload to OpenAI for medical recommendation
        response = client.chat.completions.create(
            model="gpt-3.5-turbo",
            response_format={"type": "json_object"},
            messages=[{"role": "user",
                       "content": f"Please provide me with a medical recommendation in JSON format. {request_payload_str}"}]
        )

        # Fetch the result as a JSON string
        json_result = response.choices[0].message.content

        # Parse the JSON string to a Python dictionary
        result = json.loads(json_result)

        return JSONResponse(content=result, status_code=200)

    except Exception as e:
        # If an error occurs, return an HTTP 500 error with the error message
        raise HTTPException(status_code=500, detail=str(e))


'''
# Example usage:
json_payload = {
    "descripcion": {
        "idioma": "es-EN",
        "texto": "Necesito una recomendación médica para mis síntomas."
    },
    "persona": {
        "tipoPersona": "Adulto"
    },
    "sintomas": {
        "sintoma1": "Dolor de cabeza",
        "sintoma2": "Fiebre alta",
        "sintoma3": "Dolor de garganta",
        "sintoma4": "Tos persistente con flema"
    },
    "formatoResultado": {
        "formato": {
            "recomendaciones": [
                {
                    "sintoma": "",
                    "tratamiento": "",
                    "nombre del medicamento": "",
                    "mg": " mg"
                }
            ]
        }
    }
}

# Call the function with the JSON payload
login_sp(json_payload)
'''