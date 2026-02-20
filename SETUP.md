# Lumina Photo Vault — Setup Guide

## Project Structure

```
photo_viewer/
├── app.py              # Flask application
├── requirements.txt    # Python dependencies
├── .env.example        # Environment variable template
├── .env                # Your config (never commit this!)
└── templates/
    └── index.html      # UI template
```

---

## Step 1 — Create an AWS Account

1. Go to [https://aws.amazon.com](https://aws.amazon.com) and click **Create an AWS Account**
2. Follow the sign-up steps (you'll need a credit card, but S3 has a generous free tier: 5 GB free for 12 months)
3. Once created, sign in to the **AWS Management Console**

---

## Step 2 — Create an S3 Bucket

1. In the AWS Console, search for **S3** and open it
2. Click **Create bucket**
3. **Bucket name**: choose a unique, lowercase name (e.g. `my-photo-vault-2024`) — names are globally unique across all AWS accounts
4. **AWS Region**: choose a region close to you (e.g. `us-east-1` for US East)
5. **Block Public Access**: keep all public access **blocked** (the app streams photos through Flask, not directly from S3)
6. Leave all other settings as default and click **Create bucket**

---

## Step 3 — Create an IAM User (for API access)

Never use your root AWS account for API keys. Create a dedicated user:

1. In the AWS Console, search for **IAM** and open it
2. Go to **Users** → **Create user**
3. **User name**: e.g. `lumina-photo-app`
4. Click **Next** (no console access needed)
5. **Set permissions**: choose **Attach policies directly**
6. Search for and select **AmazonS3FullAccess** (or see the minimal policy below)
7. Click **Next** → **Create user**

### Create Access Keys

1. Click on your new user → **Security credentials** tab
2. Scroll to **Access keys** → **Create access key**
3. Choose **Application running outside AWS**
4. **Save the Access Key ID and Secret Access Key** — you won't see the secret again!

### Minimal S3 Policy (optional, more secure than FullAccess)

Instead of `AmazonS3FullAccess`, you can attach this custom policy — replace `your-bucket-name`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::your-bucket-name"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::your-bucket-name/*"
    }
  ]
}
```

---

## Step 4 — Configure the App

1. Copy the example env file:
   ```bash
   cp .env.example .env
   ```

2. Open `.env` and fill in your values:
   ```
   S3_BUCKET_NAME=your-bucket-name
   AWS_REGION=us-east-1
   AWS_ACCESS_KEY_ID=your-access-key-id
   AWS_SECRET_ACCESS_KEY=your-secret-access-key
   SECRET_KEY=some-random-string-here
   ```

---

## Step 5 — Install & Run

```bash
# Create a virtual environment (recommended)
python -m venv venv
source venv/bin/activate        # macOS/Linux
venv\Scripts\activate           # Windows

# Install dependencies
pip install -r requirements.txt

# Load env vars and run
python app.py
```

Open your browser to: **http://localhost:5000**

---

## Features

| Feature | Details |
|---|---|
| 📤 Upload | Drag & drop or click to browse. Supports PNG, JPG, WEBP, GIF, BMP, TIFF, SVG |
| 🖼 Browse | Responsive grid gallery with hover previews |
| 🔍 Lightbox | Click any photo to view full-size |
| ⬇️ Download | Download original files directly from S3 |
| 🗑 Delete | Remove photos from S3 with confirmation prompt |

---

## Deploying to Production

When you're ready to share the app publicly:

**Recommended: Railway or Render (free tiers available)**

1. Push your code to GitHub (make sure `.env` is in `.gitignore`!)
2. Connect the repo to [Railway](https://railway.app) or [Render](https://render.com)
3. Set environment variables in their dashboard (same as your `.env` file)
4. Deploy!

**Never commit your `.env` file or AWS credentials to Git.**
