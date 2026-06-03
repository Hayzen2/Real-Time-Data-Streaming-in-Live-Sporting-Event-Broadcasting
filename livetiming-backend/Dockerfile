FROM python:3.11-slim

WORKDIR /app

# Initialize virtual environment and install required libraries
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the entire backend source code into the container
COPY . .

# Run FastAPI server using Uvicorn
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
