import express from "express"
import { render } from "@antv/gpt-vis-ssr"
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3"
import dotenv from "dotenv"
import { v4 as uuidv4 } from "uuid"

dotenv.config()

const app = express()
const port = 3000

const s3Client = new S3Client({
  endpoint: process.env.AWS_ENDPOINT,
  region: process.env.AWS_REGION || "us-east-1", // Using AWS_REGION for MinIO region
  credentials: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID || "",
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY || "",
  },
  forcePathStyle: true, // Required for MinIO
})

app.use(express.json())

app.post("/generate-chart", async (req, res) => {
  const vis = await render(req.body)
  const buffer = vis.toBuffer()

  const bucketName = process.env.S3_BUCKET_NAME // Using S3_BUCKET_NAME for MinIO bucket name

  if (!bucketName) {
    console.error("S3_BUCKET_NAME is not defined in environment variables.")
    return res.status(500).json({
      success: false,
      message: "MinIO bucket name not configured.",
    })
  }

  const fileName = `charts/${uuidv4()}.png`

  const uploadParams = {
    Bucket: bucketName,
    Key: fileName,
    Body: buffer,
    ContentType: "image/png",
  }

  s3Client
    .send(new PutObjectCommand(uploadParams))
    .then(() => {
      console.log(`File uploaded successfully to MinIO: ${fileName}`)
      const imageUrl = `${process.env.AWS_ENDPOINT}/${bucketName}/${fileName}` // Using AWS_ENDPOINT for MinIO URL
      res.json({
        success: true,
        resultObj: imageUrl,
      })
    })
    .catch((err) => {
      console.error("MinIOアップロードエラー:", err)
      res.status(500).json({
        success: false,
        message: "Failed to upload image to MinIO.",
      })
    })
})

app.listen(port, () => {
  console.log(`Chart server listening at http://localhost:${port}`)
})
