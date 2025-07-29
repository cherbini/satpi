<?php
/**
 * SatPi Status Handler
 * Provides status information for the upload system
 */

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

$UPLOAD_DIR = '/var/www/html/satellite/raw/';
$LOG_FILE = '/var/log/satpi-uploads.log';

// Get directory statistics
$total_files = 0;
$total_size = 0;
$recent_files = [];

if (is_dir($UPLOAD_DIR)) {
    $files = glob($UPLOAD_DIR . '*.raw');
    $total_files = count($files);
    
    foreach ($files as $file) {
        $size = filesize($file);
        $total_size += $size;
        
        $recent_files[] = [
            'filename' => basename($file),
            'size' => $size,
            'modified' => date('c', filemtime($file))
        ];
    }
    
    // Sort by modification time, most recent first
    usort($recent_files, function($a, $b) {
        return strtotime($b['modified']) - strtotime($a['modified']);
    });
    
    $recent_files = array_slice($recent_files, 0, 10); // Last 10 files
}

// Get recent log entries
$recent_logs = [];
if (file_exists($LOG_FILE)) {
    $log_lines = file($LOG_FILE, FILE_IGNORE_NEW_LINES);
    $recent_logs = array_slice($log_lines, -20); // Last 20 log entries
}

echo json_encode([
    'status' => 'online',
    'service' => 'SatPi Upload Service',
    'version' => '1.0',
    'timestamp' => date('c'),
    'statistics' => [
        'total_files' => $total_files,
        'total_size' => $total_size,
        'total_size_mb' => round($total_size / (1024 * 1024), 2)
    ],
    'recent_files' => $recent_files,
    'recent_logs' => $recent_logs,
    'system' => [
        'php_version' => phpversion(),
        'upload_max_filesize' => ini_get('upload_max_filesize'),
        'post_max_size' => ini_get('post_max_size'),
        'disk_free' => disk_free_space($UPLOAD_DIR)
    ]
]);
?>