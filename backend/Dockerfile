# Dockerfile

# Stage 1: Use an official lightweight Python image
FROM python:3.11-slim

# Stage 2: Set the working directory inside the container
WORKDIR /app

# Stage 3: Copy and install dependencies
# Copy the requirements file first to leverage Docker's caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Stage 4: Copy the rest of the application code
COPY . .

# Stage 5: Define the command to run the application using Gunicorn
# Gunicorn is a professional-grade server, better than Flask's built-in one.
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "1", "--threads", "8", "app:app"]