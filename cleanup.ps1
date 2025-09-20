# cleanup.ps1
# Safe Cloud Run image cleanup and deploy script

# Config
$project = "sahara-wellness-prototype"
$repo = "asia-south1-docker.pkg.dev/$project/sahara-repo/sahara-backend"
$service = "sahara-backend-service"
$region = "asia-south1"

Write-Output ""
Write-Output "Checking current deployed image on Cloud Run..."
$deployedImage = & gcloud run services describe $service --project $project --region $region --format="value(spec.template.spec.containers[0].image)"

if (-not $deployedImage) {
    Write-Error "Failed to retrieve deployed image. Aborting."
    exit 1
}
Write-Output ("Currently deployed image: {0}" -f $deployedImage)

# Step 1: Build latest image
Write-Output ""
Write-Output "Building latest Docker image..."
& gcloud builds submit --tag $repo --project $project
if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed. Aborting."
    exit 1
}
Write-Output "Build successful."

# Step 2: Deploy to Cloud Run
Write-Output ""
Write-Output "Deploying new image to Cloud Run..."
& gcloud run deploy $service --image $repo --region $region --project $project --platform managed --allow-unauthenticated
if ($LASTEXITCODE -ne 0) {
    Write-Error "Deployment failed. Aborting."
    exit 1
}
Write-Output "Deployment successful."

# Step 3: Get updated image list
Write-Output ""
Write-Output "Fetching image list from Artifact Registry..."
$imagesJson = & gcloud artifacts docker images list $repo --project $project --include-tags --format="json"

if (-not $imagesJson) {
    Write-Error "No images found in $repo. Exiting."
    exit 1
}

try {
    $images = $imagesJson | ConvertFrom-Json
} catch {
    Write-Error "Failed to parse image list as JSON."
    exit 1
}

# Sort by createTime descending
$sorted = $images | Sort-Object @{ Expression = { [DateTime]::Parse($_.createTime) } } -Descending

if ($sorted.Count -lt 2) {
    Write-Output "Less than two images found. Nothing to delete."
    exit 0
}

$previousImage = $sorted[1]
$targetVersion = $previousImage.version
$targetImage = "$repo@$targetVersion"

# Step 4: Safe delete check
Write-Output ""
Write-Output "Checking if previous image is safe to delete..."
if ($deployedImage -eq $targetImage) {
    Write-Output "Skipping delete: $targetImage is currently deployed in Cloud Run."
} else {
    Write-Output "Safe to delete: $targetImage is not deployed."
    Write-Output "Deleting unused image..."
    & gcloud artifacts docker images delete $targetImage --project $project --quiet --delete-tags
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to delete $targetImage"
        exit 1
    }
    Write-Output ("Deleted: {0}" -f $targetImage)
}

Write-Output ""
Write-Output "All steps completed successfully."
