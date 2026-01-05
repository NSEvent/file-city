import sys
import struct
import random
import hashlib
import math

def clamp(val, min_val, max_val):
    return max(min_val, min(max_val, val))

def generate_tga(seed_text, output_path, width=256, height=256):
    # Hash the seed to get deterministic randomness
    hasher = hashlib.md5(seed_text.encode('utf-8'))
    seed_val = int(hasher.hexdigest(), 16)
    random.seed(seed_val)

    pixel_data = bytearray(width * height * 3)
    
    lower_seed = seed_text.lower()
    
    # Theme Logic
    if "tiktok" in lower_seed:
        theme_tiktok(pixel_data, width, height)
    elif "file-city" in lower_seed or "file city" in lower_seed:
        theme_file_city(pixel_data, width, height)
    elif "pokemon" in lower_seed:
        theme_pokemon(pixel_data, width, height)
    elif "msg" in lower_seed or "chat" in lower_seed:
        theme_imessage(pixel_data, width, height)
    elif "rust" in lower_seed:
        theme_rust(pixel_data, width, height)
    elif "python" in lower_seed:
        theme_python(pixel_data, width, height)
    elif "ios" in lower_seed or "app" in lower_seed:
        theme_ios(pixel_data, width, height)
    elif any(x in lower_seed for x in ["ai", "bot", "gpt", "intelligence", "model"]):
        theme_ai(pixel_data, width, height)
    elif any(x in lower_seed for x in ["bank", "money", "finance", "gold", "cash", "price", "card", "calc", "budget"]):
        theme_finance(pixel_data, width, height)
    elif any(x in lower_seed for x in ["real", "estate", "house", "mortgage", "rent", "landlord", "zillow"]):
        theme_real_estate(pixel_data, width, height)
    elif any(x in lower_seed for x in ["audio", "voice", "sound", "speech", "say", "dtmf", "mouth"]):
        theme_audio(pixel_data, width, height)
    elif any(x in lower_seed for x in ["camera", "photo", "image", "video", "face", "glitch"]):
        theme_camera(pixel_data, width, height)
    elif any(x in lower_seed for x in ["web", "chrome", "browser", "link", "site", "scrape"]):
        theme_web(pixel_data, width, height)
    else:
        theme_default(pixel_data, width, height, seed_val)

    # TGA Header (Uncompressed TrueColor)
    header = bytearray(18)
    header[2] = 2 # Image Type: Uncompressed True-Color
    header[12] = width & 0xFF
    header[13] = (width >> 8) & 0xFF
    header[14] = height & 0xFF
    header[15] = (height >> 8) & 0xFF
    header[16] = 24 # Bits per pixel
    header[17] = 0 

    with open(output_path, 'wb') as f:
        f.write(header)
        f.write(pixel_data)
    
    print(f"Generated {output_path} for '{seed_text}'")

# --- Themes ---

def theme_tiktok(pixels, w, h):
    for i in range(0, len(pixels), 3):
        pixels[i] = 20; pixels[i+1] = 20; pixels[i+2] = 20
    def shape(x, y):
        nx, ny = x + 40, y + 40
        return (math.sqrt((nx-40)**2 + (ny-160)**2) < 30) or (60 < nx < 80 and 40 < ny < 160)
    for y in range(h):
        for x in range(w):
            idx = (y * w + x) * 3
            cx, cy = x - w//2, y - h//2
            r, g, b = pixels[idx+2], pixels[idx+1], pixels[idx]
            if shape(cx + 5, cy): b, g = 255, 255
            if shape(cx - 5, cy): r = 255
            if shape(cx, cy): 
                if r == 255 and b == 255: g = 255
            pixels[idx] = b; pixels[idx+1] = g; pixels[idx+2] = r

def theme_file_city(pixels, w, h):
    for y in range(h):
        for x in range(w):
            nx, ny = x/w, y/h
            r, g, b = 50, 100, 200
            if 0.1 < nx < 0.9 and 0.1 < ny < 0.9:
                r, g, b = 80, 80, 220
                if 0.2 < nx < 0.8 and 0.55 < ny < 0.9: r, g, b = 240, 240, 240
                if 0.25 < nx < 0.75 and 0.1 < ny < 0.4:
                    r, g, b = 180, 180, 190
                    if 0.3 < nx < 0.45 and 0.15 < ny < 0.35: r, g, b = 40, 40, 40
            idx = (y * w + x) * 3
            pixels[idx] = b; pixels[idx+1] = g; pixels[idx+2] = r

def theme_pokemon(pixels, w, h):
    for y in range(h):
        for x in range(w):
            dx, dy = x - w//2, y - h//2
            dist = math.sqrt(dx*dx + dy*dy)
            r, g, b = 200, 200, 200
            if dist < 110:
                if dy < -10: r, g, b = 220, 40, 40
                elif dy > 10: r, g, b = 240, 240, 240
                else: r, g, b = 20, 20, 20
                if dist < 30:
                    r, g, b = 20, 20, 20
                    if dist < 20: r, g, b = 255, 255, 255
            idx = (y * w + x) * 3
            pixels[idx] = b; pixels[idx+1] = g; pixels[idx+2] = r

def theme_imessage(pixels, w, h):
    for y in range(h):
        for x in range(w):
            dx, dy = x - w//2, y - h//2
            r, g, b = 255, 255, 255
            if (abs(dx) < 80 and abs(dy) < 50):
                grad = y / h
                r, g, b = 0, int(120 + grad * 50), 255
            if 160 < x < 190 and 150 < y < 180 and x - 160 < 180 - y:
                r, g, b = 0, 120, 255
            idx = (y * w + x) * 3
            pixels[idx] = b; pixels[idx+1] = g; pixels[idx+2] = r

def theme_rust(pixels, w, h):
    for y in range(h):
        for x in range(w):
            r, g, b = 40, 40, 40
            dx, dy = x - w//2, y - h//2
            if math.sqrt(dx*dx + dy*dy) < 80:
                r, g, b = 180 + random.randint(0, 50), 90 + random.randint(0, 50), 40
                if x % 40 > 30: r -= 40; g -= 20
            idx = (y * w + x) * 3
            pixels[idx] = b; pixels[idx+1] = g; pixels[idx+2] = r

def theme_python(pixels, w, h):
    for y in range(h):
        for x in range(w):
            r, g, b = 50, 50, 50
            ny = y / 20.0
            sinx = math.sin(ny) * 20.0
            if abs((x - w/3) + sinx) < 15: r, g, b = 50, 100, 200
            if abs((x - 2*w/3) - sinx) < 15: r, g, b = 220, 200, 50
            idx = (y * w + x) * 3
            pixels[idx] = b; pixels[idx+1] = g; pixels[idx+2] = r

def theme_ios(pixels, w, h):
    for y in range(h):
        for x in range(w):
            r, g, b = 240, 240, 240
            gx, gy = x % 64, y % 64
            if 10 < gx < 54 and 10 < gy < 54:
                r = (x * 5) % 255; g = (y * 5) % 255; b = 200
            idx = (y * w + x) * 3
            pixels[idx] = b; pixels[idx+1] = g; pixels[idx+2] = r

def theme_ai(pixels, w, h):
    for y in range(h):
        for x in range(w):
            r, g, b = 0, 20, 0
            if x % 30 == 0 or y % 30 == 0: r, g, b = 0, 150, 0
            if x % 60 == 0 and y % 60 == 0: r, g, b = 100, 255, 100
            idx = (y * w + x) * 3
            pixels[idx] = b; pixels[idx+1] = g; pixels[idx+2] = r

def theme_finance(pixels, w, h):
    for y in range(h):
        for x in range(w):
            r, g, b = 240, 255, 240
            chart_y = h - (x / w) * (h * 0.8) - 20 + math.sin(x/10.0)*20
            if abs(y - chart_y) < 2: r, g, b = 0, 180, 0
            elif y > chart_y: r, g, b = 200, 250, 200
            idx = (y * w + x) * 3
            pixels[idx] = b; pixels[idx+1] = g; pixels[idx+2] = r

def theme_real_estate(pixels, w, h):
    # Brick red with roof
    for y in range(h):
        for x in range(w):
            r, g, b = 180, 80, 60 # Brick
            if (x // 20 + y // 10) % 2 == 0: r -= 20; g -= 10
            
            # Roof
            if y < h/3:
                 dx = x - w/2
                 roof_y = abs(dx)
                 if y > roof_y:
                     r, g, b = 80, 40, 30
            
            idx = (y * w + x) * 3
            pixels[idx] = b; pixels[idx+1] = g; pixels[idx+2] = r

def theme_audio(pixels, w, h):
    # Waveform
    for y in range(h):
        for x in range(w):
            r, g, b = 20, 20, 30
            amp = math.sin(x/10.0) * math.sin(x/50.0) * (h/3)
            if abs(y - h/2) < abs(amp):
                r, g, b = 100, 200, 255
            idx = (y * w + x) * 3
            pixels[idx] = b; pixels[idx+1] = g; pixels[idx+2] = r

def theme_camera(pixels, w, h):
    # Aperture
    for y in range(h):
        for x in range(w):
            dx, dy = x - w/2, y - h/2
            dist = math.sqrt(dx*dx + dy*dy)
            r, g, b = 50, 50, 50
            if dist < 100:
                angle = math.atan2(dy, dx)
                r, g, b = 20, 20, 20
                if int(angle * 6) % 2 == 0:
                    r, g, b = 40, 40, 40
                if dist < 40: # Lens
                     r, g, b = 20, 0, 80
            idx = (y * w + x) * 3
            pixels[idx] = b; pixels[idx+1] = g; pixels[idx+2] = r

def theme_web(pixels, w, h):
    # Grid/Globe
    for y in range(h):
        for x in range(w):
            r, g, b = 255, 255, 255
            # Latitude/Longitude
            if x % 30 == 0 or y % 30 == 0:
                 r, g, b = 200, 200, 255
            # "Browser" header
            if y < 40:
                r, g, b = 220, 220, 220
                if x > 200: r, g, b = 255, 100, 100 # Close btn
            idx = (y * w + x) * 3
            pixels[idx] = b; pixels[idx+1] = g; pixels[idx+2] = r

def theme_default(pixels, w, h, seed_val):
    r_base = random.randint(50, 200)
    g_base = random.randint(50, 200)
    b_base = random.randint(50, 200)
    for y in range(h):
        for x in range(w):
            scale = 32
            check = ((x // scale) + (y // scale)) % 2
            noise = random.randint(-20, 20)
            r = clamp(r_base + (40 if check else 0) + noise, 0, 255)
            g = clamp(g_base + (40 if check else 0) + noise, 0, 255)
            b = clamp(b_base + (40 if check else 0) + noise, 0, 255)
            wx, wy = x % 32, y % 32
            if 10 < wx < 22 and 10 < wy < 22: r, g, b = 255, 255, 200
            idx = (y * w + x) * 3
            pixels[idx] = b; pixels[idx+1] = g; pixels[idx+2] = r

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 nano_banana.py <seed_text> <output_path>")
        sys.exit(1)
    generate_tga(sys.argv[1], sys.argv[2])