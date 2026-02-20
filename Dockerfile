# Use AWS's official Lambda Python base image
FROM public.ecr.aws/lambda/python:3.12

# Copy dependencies first (better layer caching)
COPY requirements.txt .
RUN pip install -r requirements.txt --target "${LAMBDA_TASK_ROOT}" --no-cache-dir

# Copy app code and templates
COPY app.py ${LAMBDA_TASK_ROOT}/
COPY templates/ ${LAMBDA_TASK_ROOT}/templates/

# Lambda handler entrypoint (module.attribute)
CMD ["app.handler"]
