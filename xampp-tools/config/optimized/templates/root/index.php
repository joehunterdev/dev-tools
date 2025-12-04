<?php
// XAMPP Environment Dashboard with VHosts and File Browser
// Load environment configuration
error_reporting(E_ALL);
ini_set('display_errors', 1);

$env_file = __DIR__ . '/../../../.env';
$env_vars = array();
if (file_exists($env_file)) {
    $env_content = file_get_contents($env_file);
    preg_match_all('/^([A-Z_]+)=(.+)$/m', $env_content, $matches);
    for ($i = 0; $i < count($matches[1]); $i++) {
        $env_vars[$matches[1][$i]] = trim($matches[2][$i], '\'"');
    }
}

$config = array(
    'xampp_port' => $env_vars['XAMPP_SERVER_PORT'] ?? 8080,
    'mysql_port' => $env_vars['MYSQL_PORT'] ?? 3306,
    'vhosts_extension' => $env_vars['VHOSTS_EXTENSION'] ?? '.local',
    'php_version' => phpversion(),
    'server_software' => $_SERVER['SERVER_SOFTWARE'] ?? 'Unknown',
    'document_root' => $_SERVER['DOCUMENT_ROOT'] ?? 'Unknown',
    'server_name' => $_SERVER['SERVER_NAME'] ?? 'Unknown',
    'remote_addr' => $_SERVER['REMOTE_ADDR'] ?? 'Unknown'
);

// Load VHosts configuration
$vhosts = array();
$vhosts_file = 'c:\\dev-tools\\xampp-tools\\config\\vhosts.json';

if (file_exists($vhosts_file)) {
    $vhosts_data = json_decode(file_get_contents($vhosts_file), true);
    $raw_vhosts = $vhosts_data['vhosts'] ?? array();
    
    // Derive serverName from folder + VHOSTS_EXTENSION
    foreach ($raw_vhosts as $vhost) {
        // If serverName already set, use it; otherwise derive from folder
        if (empty($vhost['serverName'])) {
            $folder = $vhost['folder'] ?? '';
            if ($folder === '.') {
                $vhost['serverName'] = 'localhost';
            } else {
                // Extract base name (remove any existing extension like .house, .dev, etc)
                $baseName = preg_replace('/\.[a-zA-Z0-9]+$/', '', $folder);
                $vhost['serverName'] = $baseName . $config['vhosts_extension'];
            }
        }
        $vhosts[] = $vhost;
    }
}

// Prepend default localhost entry
array_unshift($vhosts, array(
    'name' => 'Default (localhost)',
    'serverName' => 'localhost',
    'folder' => '.',
    'type' => 'default'
));

// File browser functionality - disable custom browser, use Apache default
// This allows Apache to handle directory listings naturally
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>XAMPP Dashboard</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
            color: #333;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        
        .header {
            text-align: center;
            color: white;
            margin-bottom: 30px;
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        
        .header p {
            font-size: 1.1em;
            opacity: 0.9;
        }
        
        .quick-access {
            display: flex;
            gap: 10px;
            justify-content: center;
            margin-bottom: 30px;
            flex-wrap: wrap;
        }
        
        .btn {
            display: inline-block;
            padding: 10px 20px;
            background: white;
            color: #667eea;
            text-decoration: none;
            border-radius: 5px;
            border: none;
            cursor: pointer;
            font-weight: bold;
            transition: all 0.3s ease;
            font-size: 0.9em;
        }
        
        .btn:hover {
            background: #667eea;
            color: white;
            transform: translateY(-2px);
        }
        
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .card {
            background: white;
            border-radius: 8px;
            padding: 20px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            transition: transform 0.3s ease, box-shadow 0.3s ease;
        }
        
        .card:hover {
            transform: translateY(-5px);
            box-shadow: 0 15px 40px rgba(0,0,0,0.3);
        }
        
        .card h2 {
            color: #667eea;
            font-size: 1.4em;
            margin-bottom: 15px;
            border-bottom: 2px solid #667eea;
            padding-bottom: 10px;
        }
        
        .card-item {
            margin: 10px 0;
            padding: 8px;
            background: #f8f9fa;
            border-left: 3px solid #667eea;
            border-radius: 4px;
            font-size: 0.95em;
        }
        
        .card-item strong {
            color: #667eea;
        }
        
        .card-item a {
            color: #667eea;
            text-decoration: none;
            font-weight: bold;
        }
        
        .card-item a:hover {
            text-decoration: underline;
        }
        
        .section-title {
            color: white;
            font-size: 1.8em;
            margin-top: 30px;
            margin-bottom: 20px;
            padding-left: 10px;
            border-left: 4px solid white;
        }
        
        .sites-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
            gap: 12px;
            margin-bottom: 30px;
        }
        
        .site-card {
            background: white;
            border-radius: 8px;
            padding: 15px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
            border-left: 4px solid #667eea;
            cursor: pointer;
            transition: all 0.3s ease;
            text-align: center;
        }
        
        .site-card:hover {
            transform: translateY(-3px);
            box-shadow: 0 8px 20px rgba(0,0,0,0.15);
            background: #f8f9fa;
        }
        
        .site-card.active {
            border-left-color: #764ba2;
            background: #f0e8f7;
        }
        
        .site-name {
            font-size: 1em;
            font-weight: bold;
            color: #667eea;
            margin-bottom: 8px;
            word-break: break-word;
        }
        
        .site-url {
            font-size: 0.75em;
            color: #999;
            font-family: 'Courier New', monospace;
            margin-bottom: 8px;
        }
        
        .site-type {
            display: inline-block;
            background: #667eea;
            color: white;
            padding: 2px 8px;
            border-radius: 12px;
            font-size: 0.7em;
        }
        
        footer {
            text-align: center;
            color: white;
            margin-top: 40px;
            padding: 20px;
            opacity: 0.8;
            font-size: 0.9em;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Dev-Tools Dashboard</h1>
            <p>Local development environment</p>
        </div>
        
        <div class="quick-access">
            <a href="phpinfo.php" class="btn" target="_blank">📊 PHP Info</a>
            <a href="http://localhost:<?php echo $config['xampp_port']; ?>/phpmyadmin/" class="btn" target="_blank">💾 phpMyAdmin</a>
            <a href="." class="btn">🏠 Refresh</a>
        </div>
        
        <div class="grid">
            <!-- Server Info Card -->
            <div class="card">
                <h2>Server</h2>
                <div class="card-item"><strong>Software:</strong> <?php echo htmlspecialchars($config['server_software']); ?></div>
                <div class="card-item"><strong>PHP:</strong> <?php echo htmlspecialchars($config['php_version']); ?></div>
                <div class="card-item"><strong>Port:</strong> <?php echo htmlspecialchars($config['xampp_port']); ?></div>
                <div class="card-item"><strong>MySQL:</strong> <?php echo htmlspecialchars($config['mysql_port']); ?></div>
            </div>
            
            <!-- Network Card -->
            <div class="card">
                <h2>Network</h2>
                <div class="card-item"><strong>Host:</strong> <?php echo htmlspecialchars($config['server_name']); ?></div>
                <div class="card-item"><strong>Client IP:</strong> <?php echo htmlspecialchars($config['remote_addr']); ?></div>
                <div class="card-item"><strong>Root:</strong> <?php echo htmlspecialchars(basename($config['document_root'])); ?></div>
                <div class="card-item"><strong>Time:</strong> <?php echo date('H:i:s'); ?></div>
            </div>
            
            <!-- Environment Card -->
            <div class="card">
                <h2>Environment</h2>
                <div class="card-item"><strong>Memory:</strong> <?php echo ini_get('memory_limit'); ?></div>
                <div class="card-item"><strong>Upload:</strong> <?php echo ini_get('upload_max_filesize'); ?></div>
                <div class="card-item"><strong>Timezone:</strong> <?php echo date_default_timezone_get(); ?></div>
                <div class="card-item"><strong>Date:</strong> <?php echo date('Y-m-d'); ?></div>
            </div>
        </div>
        
        <div class="section-title">🌐 Configured Sites</div>
        <div class="sites-grid">
            <?php 
            foreach ($vhosts as $vhost):
                // Derive serverName from folder or use existing serverName
                if (isset($vhost['serverName'])) {
                    $serverName = $vhost['serverName'];
                } else {
                    // Generate from folder name + extension
                    $folder = $vhost['folder'] ?? 'localhost';
                    $serverName = ($folder === '.' || $folder === '') ? 'localhost' : $folder . $config['vhosts_extension'];
                }
                
                $siteUrl = 'http://' . $serverName . ':' . $config['xampp_port'] . '/';
                $siteName = $vhost['name'] ?? $serverName;
            ?>
                <div class="site-card" onclick="window.open('<?php echo $siteUrl; ?>', '_blank')">
                    <div class="site-name"><?php echo htmlspecialchars($siteName); ?></div>
                    <div class="site-url"><?php echo htmlspecialchars($serverName); ?></div>
                    <div class="site-type"><?php echo htmlspecialchars($vhost['type']); ?></div>
                </div>
            <?php endforeach; ?>
        </div>
        
        <footer>
            <p>🔒 Development environment - do not use in production</p>
        </footer>
    </div>
</body>
</html>
