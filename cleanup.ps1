param(
    [string]$project = "sahara-wellness-prototype",
    [string]$repo = "asia-south1-docker.pkg.dev/sahara-wellness-prototype/sahara-repo/sahara-backend",
    [int]$keep = 2
)

Write-Output "Fetching image list from $repo..."

# Get clean JSON
$imagesJson = gcloud artifacts docker images list $repo `
    --project $project `
    --include-tags `
    --format="json"

if (-not $imagesJson) {
    Write-Output "No images found in $repo. Exiting."
    exit 0
}

# Parse JSON
try {
    $images = $imagesJson | ConvertFrom-Json
} catch {
    Write-Error "Failed to parse JSON. Raw output:`n$imagesJson"
    exit 1
}

# Sort by createTime (newest first)
$sorted = $images | Sort-Object { [DateTime]::Parse($_.createTime) } -Descending

# Split into keep & delete sets
$toKeep = $sorted | Select-Object -First $keep
$toDelete = $sorted | Select-Object -Skip $keep

Write-Output "Keeping $($toKeep.Count) latest images."
Write-Output "Deleting $($toDelete.Count) old images..."

foreach ($img in $toDelete) {
    $version = $img.version
    Write-Output "Deleting: $repo@$version"
    gcloud artifacts docker images delete "$repo@$version" `
        --project $project `
        --quiet `
        --delete-tags
}

Write-Output "✅ Cleanup complete!"
