# SSL Implementation - XAMPP on Windows with Multiple Virtual Hosts

## Overview
This guide covers setting up self-signed SSL certificates for localhost and multiple virtual hosts in XAMPP on Windows. Self-signed certificates expire after 365 days, so this process needs to be repeated annually (or set a longer expiry).

## The 8-Step Process

### Step 1: Edit PHP and Apache Configuration

#### Enable OpenSSL in php.ini
1. Open `C:\xampp\php\php.ini`
2. Find the line containing `extension=openssl`
3. Remove the semicolon (`;`) at the start if present
4. Save the file

#### Enable Rewrite Module in httpd.conf
1. Open `C:\xampp\apache\conf\httpd.conf`
2. Ensure this line is uncommented (no `;` at start):
   ```
   LoadModule rewrite_module modules/mod_rewrite.so
   ```
3. Save the file

---

### Step 2: Create a Certificate Generation Script

Create a batch script `C:\xampp\apache\makecert_bulk.bat` to automate certificate generation:

```batch
set XAMPPDIR=C:\xampp
set HOME=%XAMPPDIR%\apache\conf
set OPENSSL_CONF=%HOME%\openssl.cnf
if not exist %HOME%\ssl.crt mkdir %HOME%\ssl.crt
if not exist %HOME%\ssl.key mkdir %HOME%\ssl.key

set V3_EXT=subjectAltName=DNS:localhost,DNS:127.0.0.1,DNS:local.website1,DNS:local.website2

set DOMAIN=localhost
bin\openssl req -subj "/C=AU/ST=NSW/L=Sydney/O=Your Organization/OU=/CN=%DOMAIN%" -x509 -addext %V3_EXT% -nodes -days 365 -newkey rsa:2048 -keyout %HOME%\ssl.key\%DOMAIN%-selfsigned.key -out %HOME%\ssl.crt\%DOMAIN%-selfsigned.crt

set DOMAIN=local.website1
bin\openssl req -subj "/C=AU/ST=NSW/L=Sydney/O=Your Organization/OU=/CN=%DOMAIN%" -x509 -addext %V3_EXT% -nodes -days 365 -newkey rsa:2048 -keyout %HOME%\ssl.key\%DOMAIN%-selfsigned.key -out %HOME%\ssl.crt\%DOMAIN%-selfsigned.crt

set DOMAIN=local.website2
bin\openssl req -subj "/C=AU/ST=NSW/L=Sydney/O=Your Organization/OU=/CN=%DOMAIN%" -x509 -addext %V3_EXT% -nodes -days 365 -newkey rsa:2048 -keyout %HOME%\ssl.key\%DOMAIN%-selfsigned.key -out %HOME%\ssl.crt\%DOMAIN%-selfsigned.crt
```

**Key Notes:**
- Change `C=AU/ST=NSW/L=Sydney/O=Your Organization` to match your location
- Only the `/CN=%DOMAIN%` value is critical
- Add a new `set DOMAIN=` block for each additional virtual host
- If openssl is in your PATH, remove `bin\` prefix

---

### Step 3: Generate Certificates

1. Open Command Prompt
2. Navigate to XAMPP Apache directory:
   ```cmd
   cd /D C:\xampp\apache
   ```
3. Run the certificate script:
   ```cmd
   makecert_bulk
   ```
4. Certificates will be created in:
   - `C:\xampp\apache\conf\ssl.crt\` (public certificates)
   - `C:\xampp\apache\conf\ssl.key\` (private keys)

---

### Step 4: Import Certificates to Windows Certificate Store

1. Open Certificate Manager:
   - Press `Win + R` and type `certmgr.msc`
2. Navigate to: **Trusted Root Certification Authorities → Certificates**
3. Right-click "Certificates" → **All Tasks → Import...**
4. For each certificate (localhost-selfsigned.crt, local.website1-selfsigned.crt, etc.):
   - Click **Browse** and select the `.crt` file from `C:\xampp\apache\conf\ssl.crt\`
   - Click **Next** through all steps
   - Click **Finish** and confirm the security warning with **Yes**

---

### Step 5: Configure httpd-ssl.conf

1. Open `C:\xampp\apache\conf\extra\httpd-ssl.conf`
2. Find the `SSLCertificateFile` and `SSLCertificateKeyFile` directives
3. Comment out the defaults and add your certificates:

```apache
# Comment out default
#SSLCertificateFile "conf/ssl.crt/server.crt"
#SSLCertificateKeyFile "conf/ssl.key/server.key"

# Add your certificates
SSLCertificateFile "conf/ssl.crt/localhost-selfsigned.crt"
SSLCertificateFile "conf/ssl.crt/local.website1-selfsigned.crt"
SSLCertificateFile "conf/ssl.crt/local.website2-selfsigned.crt"

SSLCertificateKeyFile "conf/ssl.key/localhost-selfsigned.key"
SSLCertificateKeyFile "conf/ssl.key/local.website1-selfsigned.key"
SSLCertificateKeyFile "conf/ssl.key/local.website2-selfsigned.key"
```

---

### Step 6: Configure Virtual Hosts (httpd-vhosts.conf)

1. Open `C:\xampp\apache\conf\extra\httpd-vhosts.conf`
2. Setup HTTP to HTTPS redirect and SSL virtual hosts for each domain:

```apache
# Localhost HTTP redirect
<VirtualHost *:80>
    ServerName localhost
    Redirect / https://localhost/
</VirtualHost>

# Localhost HTTPS
<VirtualHost *:443>
    ServerName localhost
    DocumentRoot "C:/xampp/htdocs/"
    SSLEngine on
    SSLCertificateFile "C:\xampp\apache\conf\ssl.crt\localhost-selfsigned.crt"
    SSLCertificateKeyFile "C:\xampp\apache\conf\ssl.key\localhost-selfsigned.key"
</VirtualHost>

# Website 1 HTTP redirect
<VirtualHost *:80>
    ServerName local.website1
    Redirect / https://local.website1/
</VirtualHost>

# Website 1 HTTPS
<VirtualHost *:443>
    ServerName local.website1
    DocumentRoot "C:/xampp/htdocs/website1"
    SSLEngine on
    SSLCertificateFile "C:\xampp\apache\conf\ssl.crt\local.website1-selfsigned.crt"
    SSLCertificateKeyFile "C:\xampp\apache\conf\ssl.key\local.website1-selfsigned.key"
</VirtualHost>

# Website 2 HTTP redirect
<VirtualHost *:80>
    ServerName local.website2
    Redirect / https://local.website2/
</VirtualHost>

# Website 2 HTTPS
<VirtualHost *:443>
    ServerName local.website2
    DocumentRoot "C:/xampp/htdocs/website2"
    SSLEngine on
    SSLCertificateFile "C:\xampp\apache\conf\ssl.crt\local.website2-selfsigned.crt"
    SSLCertificateKeyFile "C:\xampp\apache\conf\ssl.key\local.website2-selfsigned.key"
</VirtualHost>
```

---

### Step 7: Restart XAMPP Services

1. Open XAMPP Control Panel
2. Click **Stop** on Apache and MySQL (if running)
3. Once stopped, click **Start** to restart them
4. HTTPS should now be enabled for all virtual hosts

---

### Step 8: Test and Fix Browser Issues

#### Test in Browser
- Navigate to `https://localhost`
- Other browsers (Chrome, Edge, Safari, IE11) work immediately
- Firefox requires additional setup (see below)

#### Firefox Certificate Exception

Firefox displays a security warning for self-signed certificates. To fix:

1. Go to **Tools → Settings → Privacy & Security**
2. Scroll to **Certificates** section
3. Click **View Certificates**
4. Go to **Servers** tab
5. Click **Add Exception**
6. Enter `https://localhost` and click **Get Certificate**
7. Click **Confirm Security Exception**
8. Repeat for each virtual host (e.g., `https://local.website1`)

After adding exceptions, Firefox will show a warning icon on the padlock but will allow access.

---

## Certificate Renewal

Since certificates expire after 365 days, you'll need to:
1. Update the certificate generation script with new domains
2. Run `makecert_bulk.bat` again
3. Re-import certificates to Windows Certificate Store
4. Update `httpd-ssl.conf` and `httpd-vhosts.conf` if needed
5. Restart Apache

---

## Additional Resources

- [Use HTTPS on Localhost (XAMPP, Windows)](https://gist.github.com/adnan360/ad2b1cfc44114ac6f91fbb668c76798d)
- [HTTPS for XAMPP with Self-Signed Certificates](https://paulshipley.id.au/articles/coding-tips/https-for-xampp-with-self-signed-certificates/)
- [Renew Self Signed SSL on localhost using XAMPP and Windows](https://jtowell.com.au/renew-self-signed-ssl-on-localhost-using-xampp-windows/)
