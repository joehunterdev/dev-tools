<?php
/**
 * PHP Information - Local Development Only
 * This file displays PHP configuration and installed extensions
 * REMOVE this file in production!
 */

// Security: Only allow from localhost in production-like environments
$allowed_ips = ['127.0.0.1', '::1', 'localhost'];
$client_ip = $_SERVER['REMOTE_ADDR'] ?? '';

// For development, we allow all, but this could be restricted
// if (getenv('APP_ENV') === 'production' && !in_array($client_ip, $allowed_ips)) {
//     http_response_code(403);
//     die('Access Denied');
// }

?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PHP Information</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            margin: 0;
            padding: 20px;
        }
        .container {
            max-width: 1000px;
            margin: 0 auto;
            background: white;
            border-radius: 8px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        .header h1 {
            margin: 0;
            font-size: 2em;
        }
        .header p {
            margin: 10px 0 0 0;
            opacity: 0.9;
        }
        .content {
            padding: 30px;
        }
        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .info-card {
            background: #f8f9fa;
            border-left: 4px solid #667eea;
            padding: 20px;
            border-radius: 4px;
        }
        .info-card h3 {
            margin: 0 0 10px 0;
            color: #667eea;
            font-size: 1.1em;
        }
        .info-card p {
            margin: 0;
            color: #555;
            word-break: break-all;
        }
        .php-extensions {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 4px;
            margin-top: 30px;
        }
        .php-extensions h3 {
            margin-top: 0;
            color: #667eea;
        }
        .extensions-list {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
            gap: 10px;
        }
        .extension {
            background: white;
            padding: 10px;
            border-radius: 4px;
            font-size: 0.9em;
            border: 1px solid #ddd;
        }
        .footer {
            background: #f8f9fa;
            padding: 20px;
            text-align: center;
            color: #999;
            font-size: 0.9em;
            border-top: 1px solid #ddd;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>PHP Information</h1>
            <p>Local Development Server</p>
        </div>
        
        <div class="content">
            <div class="info-grid">
                <div class="info-card">
                    <h3>PHP Version</h3>
                    <p><?php echo phpversion(); ?></p>
                </div>
                
                <div class="info-card">
                    <h3>Server Software</h3>
                    <p><?php echo $_SERVER['SERVER_SOFTWARE'] ?? 'Unknown'; ?></p>
                </div>
                
                <div class="info-card">
                    <h3>Server Name</h3>
                    <p><?php echo $_SERVER['SERVER_NAME'] ?? 'Unknown'; ?></p>
                </div>
                
                <div class="info-card">
                    <h3>Document Root</h3>
                    <p><?php echo $_SERVER['DOCUMENT_ROOT'] ?? 'Unknown'; ?></p>
                </div>
                
                <div class="info-card">
                    <h3>Current Script</h3>
                    <p><?php echo $_SERVER['SCRIPT_FILENAME'] ?? 'Unknown'; ?></p>
                </div>
                
                <div class="info-card">
                    <h3>Memory Limit</h3>
                    <p><?php echo ini_get('memory_limit'); ?></p>
                </div>
            </div>
            
            <div class="php-extensions">
                <h3>Loaded PHP Extensions</h3>
                <div class="extensions-list">
                    <?php
                    $extensions = get_loaded_extensions();
                    sort($extensions);
                    foreach ($extensions as $ext) {
                        echo '<div class="extension">' . htmlspecialchars($ext) . '</div>';
                    }
                    ?>
                </div>
            </div>
        </div>
        
        <div class="footer">
            <p>This file is for development purposes only. Remove in production.</p>
        </div>
    </div>
</body>
</html>
