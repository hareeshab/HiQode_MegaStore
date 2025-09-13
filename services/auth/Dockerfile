FROM python:3.11-slim
ENV PYTHONDONTWRITEBYTECODE=1 PIP_ROOT_USER_ACTION=ignore PIP_NO_CACHE_DIR=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --no-compile -r requirements.txt
COPY . .
EXPOSE 8001
CMD ["uvicorn","main:app","--host","0.0.0.0","--port","8001"]
