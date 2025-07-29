<?php
/**
 * SatPi Upload Handler
 * Handles satellite data uploads from Pi systems
 */

// Enable error reporting for debugging
error_reporting(E_ALL);
ini_set('display_errors', 1);

// Set response headers
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, X-API-Key');

// Handle preflight OPTIONS request
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

// Configuration
$UPLOAD_DIR = '/var/www/html/satellite/raw/';
$LOG_FILE = '/var/log/satpi-uploads.log';
$MAX_FILE_SIZE = 2147483648; // 2GB in bytes
$ALLOWED_API_KEYS = ['satpi-client', 'test-key'];

// Ensure upload directory exists
if (!is_dir($UPLOAD_DIR)) {
    mkdir($UPLOAD_DIR, 0755, true);
}

// Logging function
function log_message($message) {
    global $LOG_FILE;
    $timestamp = date('Y-m-d H:i:s');
    $log_entry = "[$timestamp] $message" . PHP_EOL;
    file_put_contents($LOG_FILE, $log_entry, FILE_APPEND | LOCK_EX);
    error_log($log_entry);
}

// Validate API key
function validate_api_key() {
    global $ALLOWED_API_KEYS;
    
    $api_key = $_SERVER['HTTP_X_API_KEY'] ?? $_POST['api_key'] ?? null;
    
    if (!$api_key || !in_array($api_key, $ALLOWED_API_KEYS)) {
        log_message("Invalid API key: " . ($api_key ?? 'none'));
        return false;
    }
    
    return true;
}

// Handle GET request (status check)
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    log_message("Status check requested");
    echo json_encode([
        'status' => 'online',
        'message' => 'SatPi Upload Service v1.0',
        'upload_dir' => $UPLOAD_DIR,
        'max_file_size' => $MAX_FILE_SIZE,
        'time' => date('c')
    ]);
    exit();
}

// Handle POST request (file upload)
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    log_message("Upload request received from " . $_SERVER['REMOTE_ADDR']);
    
    // Validate API key
    if (!validate_api_key()) {
        http_response_code(401);
        echo json_encode(['error' => 'Invalid API key']);
        exit();
    }
    
    // Check if file was uploaded
    if (!isset($_FILES['file'])) {
        log_message("No file uploaded");
        http_response_code(400);
        echo json_encode(['error' => 'No file uploaded']);
        exit();
    }
    
    $uploaded_file = $_FILES['file'];
    $metadata_raw = $_POST['metadata'] ?? $_FILES['metadata']['tmp_name'] ?? null;
    
    // Parse metadata
    $metadata = null;
    if ($metadata_raw) {
        if (is_string($metadata_raw)) {
            $metadata = json_decode($metadata_raw, true);
        } else {
            $metadata = json_decode(file_get_contents($metadata_raw), true);
        }
    }
    
    // Validate file
    if ($uploaded_file['error'] !== UPLOAD_ERR_OK) {
        log_message("Upload error: " . $uploaded_file['error']);
        http_response_code(400);
        echo json_encode(['error' => 'Upload failed: ' . $uploaded_file['error']]);
        exit();
    }
    
    if ($uploaded_file['size'] > $MAX_FILE_SIZE) {
        log_message("File too large: " . $uploaded_file['size'] . " bytes");
        http_response_code(413);
        echo json_encode(['error' => 'File too large']);
        exit();
    }
    
    // Generate filename based on metadata
    $device_id = $metadata['device_id'] ?? 'unknown';
    $satellite = $metadata['satellite'] ?? 'unknown';
    $timestamp = date('Ymd_His');
    $filename = "{$satellite}_{$device_id}_{$timestamp}.raw";
    $filepath = $UPLOAD_DIR . $filename;
    
    // Move uploaded file
    if (move_uploaded_file($uploaded_file['tmp_name'], $filepath)) {
        // Save metadata
        $metadata_file = $filepath . '.json';
        file_put_contents($metadata_file, json_encode($metadata, JSON_PRETTY_PRINT));
        
        // Create symlink for latest file from this satellite
        $latest_link = $UPLOAD_DIR . "latest_{$satellite}.raw";
        if (file_exists($latest_link)) {
            unlink($latest_link);
        }
        symlink(basename($filepath), $latest_link);
        
        $file_size = filesize($filepath);
        log_message("Upload successful: $filename ($file_size bytes) from device $device_id");
        
        echo json_encode([
            'status' => 'success',
            'message' => 'File uploaded successfully',
            'filename' => $filename,
            'size' => $file_size,
            'timestamp' => date('c')
        ]);
        
    } else {
        log_message("Failed to move uploaded file to $filepath");
        http_response_code(500);
        echo json_encode(['error' => 'Failed to save file']);
    }
    
    exit();
}

// Handle unsupported methods
http_response_code(405);
echo json_encode(['error' => 'Method not allowed']);
log_message("Unsupported method: " . $_SERVER['REQUEST_METHOD']);
?>