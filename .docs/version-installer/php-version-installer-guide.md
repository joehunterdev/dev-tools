Updating PHP in XAMPP on Windows isn’t automatic—you basically swap in a newer PHP build manually. Here’s the clean, safe way to do it:

---

## ⚠️ Before You Start

* **Back up your `htdocs` and `xampp` folder**
* Check your current version:
  Open XAMPP Control Panel → Shell → type:

  ```
  php -v
  ```

---

## 🔽 Step 1: Download Latest PHP

1. Go to the official PHP site:
   👉 [https://www.php.net/downloads.php](https://www.php.net/downloads.php)
2. Download **Thread Safe (TS)** version (important for Apache)
3. Choose the correct architecture:

   * Usually **x64** for modern systems
4. Download the **ZIP file**

---

## 📁 Step 2: Extract PHP

1. Extract the ZIP
2. Rename folder to something simple, e.g.:

   ```
   php-8.3.6
   ```

---

## 🔁 Step 3: Replace PHP in XAMPP

1. Go to your XAMPP directory:

   ```
   C:\xampp\
   ```
2. Rename current PHP folder:

   ```
   php → php_old
   ```
3. Copy your new PHP folder into `C:\xampp\`
4. Rename it to:

   ```
   php
   ```

---

## ⚙️ Step 4: Fix Apache Config

1. Open:

   ```
   C:\xampp\apache\conf\extra\httpd-xampp.conf
   ```
2. Find lines like:

   ```
   LoadFile "/xampp/php/php8ts.dll"
   LoadModule php_module "/xampp/php/php_module.dll"
   ```
3. Make sure filenames match your new PHP folder contents

---

## ⚙️ Step 5: Update php.ini

1. Inside new `php` folder:

   * Copy:

     ```
     php.ini-development → php.ini
     ```
2. Reapply any custom settings from old `php.ini`

---

## 🔌 Step 6: Enable Required Extensions

Open `php.ini` and ensure needed extensions are enabled:

```
extension=mysqli
extension=pdo_mysql
extension=openssl
```

---

## 🔄 Step 7: Restart XAMPP

* Stop Apache
* Start Apache again

---

## ✅ Step 8: Verify

Create a file in `htdocs`:

```
info.php
```

With:

```php
<?php phpinfo(); ?>
```

Open:

```
http://localhost/info.php
```

You should see the new PHP version 🎉

---

## 🚨 Common Issues

* **Apache won’t start**
  → Usually wrong DLL version or missing Visual C++ Redistributable
* **Extensions not loading**
  → Wrong `ext` path in `php.ini`
* **Thread safety mismatch**
  → Always use **Thread Safe (TS)** version with XAMPP

---

## 👍 Easier Alternative (Recommended)

If you want less hassle:

* Just download a newer XAMPP from
  Apache Friends
* Install it fresh (keeps everything compatible)

---

If you want, tell me your current PHP version and XAMPP version—I can give you exact compatible download links so nothing breaks.
