import io
import mimetypes
import os
from collections import defaultdict

import awsgi
import boto3
from botocore.exceptions import ClientError, NoCredentialsError
from flask import Flask, flash, redirect, render_template, request, send_file, url_for
from werkzeug.utils import secure_filename

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "change-me-in-production")

S3_BUCKET = os.environ.get("S3_BUCKET_NAME", "")
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
ALLOWED_EXTENSIONS = {"png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "svg"}
UNCATEGORIZED = "__uncategorized__"

def handler(event, context):
    # API Gateway v2 sends a different event format — convert it to v1
    if "requestContext" in event and "http" in event.get("requestContext", {}):
        http = event["requestContext"]["http"]
        event["httpMethod"] = http["method"]
        event["path"] = http["path"]
        event["queryStringParameters"] = event.get("queryStringParameters", {})
    return awsgi.response(app, event, context, base64_content_types={"image/png", "image/jpeg", "image/webp", "image/gif"})


def get_s3():
    return boto3.client("s3", region_name=AWS_REGION)


def allowed_file(filename):
    return "." in filename and filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTENSIONS


def is_image(key):
    ext = key.rsplit(".", 1)[-1].lower() if "." in key else ""
    return ext in ALLOWED_EXTENSIONS


def list_all_objects():
    """Return every object in the bucket, handling pagination."""
    s3 = get_s3()
    objects = []
    kwargs = {"Bucket": S3_BUCKET}
    while True:
        resp = s3.list_objects_v2(**kwargs)
        objects.extend(resp.get("Contents", []))
        if resp.get("IsTruncated"):
            kwargs["ContinuationToken"] = resp["NextContinuationToken"]
        else:
            break
    return objects


def get_albums():
    """
    Scan the bucket and group images by their top-level folder prefix.
    Root-level images go into UNCATEGORIZED.
    Returns a list of album dicts sorted alphabetically (Uncategorized last).
    """
    try:
        objects = list_all_objects()
    except (ClientError, NoCredentialsError) as e:
        flash(str(e), "error")
        return []

    # album_name -> list of photo dicts
    buckets = defaultdict(list)

    for obj in objects:
        key = obj["Key"]
        if not is_image(key):
            continue
        parts = key.split("/")
        if len(parts) == 1:
            album = UNCATEGORIZED
            filename = parts[0]
        else:
            album = parts[0]
            filename = "/".join(parts[1:])

        buckets[album].append({
            "key": key,
            "filename": filename,
            "size": obj["Size"],
            "last_modified": obj["LastModified"].strftime("%b %d, %Y"),
            "url": url_for("serve_photo", key=key),
        })

    albums = []
    for name, photos in sorted(buckets.items(), key=lambda x: (x[0] == UNCATEGORIZED, x[0].lower())):
        cover = photos[0]["url"] if photos else None
        display_name = "Uncategorized" if name == UNCATEGORIZED else name
        albums.append({
            "id": name,
            "name": display_name,
            "cover": cover,
            "count": len(photos),
        })
    return albums


def get_album_photos(album_id):
    """Return all photos belonging to a specific album."""
    try:
        objects = list_all_objects()
    except (ClientError, NoCredentialsError) as e:
        flash(str(e), "error")
        return []

    photos = []
    for obj in objects:
        key = obj["Key"]
        if not is_image(key):
            continue
        parts = key.split("/")
        if album_id == UNCATEGORIZED:
            if len(parts) != 1:
                continue
        else:
            if parts[0] != album_id:
                continue

        photos.append({
            "key": key,
            "filename": parts[-1],
            "size": obj["Size"],
            "last_modified": obj["LastModified"].strftime("%b %d, %Y"),
            "url": url_for("serve_photo", key=key),
        })
    return photos


# ── Routes ────────────────────────────────────────────────────

@app.route("/")
def index():
    albums = get_albums()
    return render_template("index.html", albums=albums, bucket=S3_BUCKET)


@app.route("/album/<path:album_id>")
def album(album_id):
    display_name = "Uncategorized" if album_id == UNCATEGORIZED else album_id
    photos = get_album_photos(album_id)
    return render_template("album.html", album_id=album_id,
                           album_name=display_name, photos=photos, bucket=S3_BUCKET)


@app.route("/photo/<path:key>")
def serve_photo(key):
    s3 = get_s3()
    try:
        obj = s3.get_object(Bucket=S3_BUCKET, Key=key)
        content_type = obj.get("ContentType") or mimetypes.guess_type(key)[0] or "image/jpeg"
        return send_file(io.BytesIO(obj["Body"].read()),
                         mimetype=content_type, as_attachment=False, download_name=key)
    except ClientError as e:
        return f"Error: {e.response['Error']['Message']}", 404


@app.route("/upload/<path:album_id>", methods=["POST"])
def upload(album_id):
    """Upload files into a specific album (S3 prefix)."""
    if "files" not in request.files:
        flash("No files selected.", "error")
        return redirect(url_for("album", album_id=album_id))

    files = request.files.getlist("files")
    s3 = get_s3()
    uploaded = 0

    for file in files:
        if file and file.filename and allowed_file(file.filename):
            filename = secure_filename(file.filename)
            # Build the S3 key: prefix/filename or just filename for uncategorized
            s3_key = filename if album_id == UNCATEGORIZED else f"{album_id}/{filename}"
            content_type = file.content_type or mimetypes.guess_type(filename)[0] or "image/jpeg"
            try:
                s3.upload_fileobj(file, S3_BUCKET, s3_key,
                                  ExtraArgs={"ContentType": content_type})
                uploaded += 1
            except (ClientError, NoCredentialsError) as e:
                flash(f"Failed to upload {filename}: {e}", "error")
        elif file.filename:
            flash(f"'{file.filename}' is not a supported format.", "warning")

    if uploaded:
        flash(f"Uploaded {uploaded} photo{'s' if uploaded > 1 else ''}!", "success")
    return redirect(url_for("album", album_id=album_id))


@app.route("/download/<path:key>")
def download(key):
    s3 = get_s3()
    try:
        obj = s3.get_object(Bucket=S3_BUCKET, Key=key)
        return send_file(io.BytesIO(obj["Body"].read()),
                         as_attachment=True, download_name=key.split("/")[-1])
    except ClientError as e:
        flash(f"Download failed: {e.response['Error']['Message']}", "error")
        return redirect(url_for("index"))


@app.route("/delete/<path:key>", methods=["POST"])
def delete(key):
    """Delete a single photo. If album becomes empty afterwards, it vanishes naturally."""
    s3 = get_s3()
    album_id = key.split("/")[0] if "/" in key else UNCATEGORIZED
    try:
        s3.delete_object(Bucket=S3_BUCKET, Key=key)
        flash(f"'{key.split('/')[-1]}' deleted.", "success")
    except ClientError as e:
        flash(f"Delete failed: {e.response['Error']['Message']}", "error")
    return redirect(url_for("album", album_id=album_id))


if __name__ == "__main__":
    app.run(debug=True, port=5000)
