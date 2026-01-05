import sys
import struct
import random
import hashlib

def generate_tga(seed_text, output_path, width=256, height=256):
    # Hash the seed to get deterministic randomness
    hasher = hashlib.md5(seed_text.encode('utf-8'))
    seed_val = int(hasher.hexdigest(), 16)
    random.seed(seed_val)

    # Base color
    r_base = random.randint(50, 200)
    g_base = random.randint(50, 200)
    b_base = random.randint(50, 200)

    pixel_data = bytearray()
    
    # TGA: Uncompressed TrueColor (Type 2)
    # Header: 18 bytes
    header = bytearray(18)
    header[2] = 2 # Image Type: Uncompressed True-Color
    header[12] = width & 0xFF
    header[13] = (width >> 8) & 0xFF
    header[14] = height & 0xFF
    header[15] = (height >> 8) & 0xFF
    header[16] = 24 # Bits per pixel
    header[17] = 0 # Image descriptor (0 means bottom-left origin)

    # Generate pixels
    # TGA usually stored B G R
    for y in range(height):
        for x in range(width):
            # Simple pattern: Checkerboard + Noise
            scale = 32
            check = ((x // scale) + (y // scale)) % 2
            
            noise = random.randint(-20, 20)
            
            r = max(0, min(255, r_base + (40 if check else 0) + noise))
            g = max(0, min(255, g_base + (40 if check else 0) + noise))
            b = max(0, min(255, b_base + (40 if check else 0) + noise))
            
            # Draw a "window" if it looks like a building
            # Windows at regular intervals
            wx = x % 32
            wy = y % 32
            if 10 < wx < 22 and 10 < wy < 22:
                 r, g, b = 255, 255, 200 # Lit window

            pixel_data.append(b)
            pixel_data.append(g)
            pixel_data.append(r)

    with open(output_path, 'wb') as f:
        f.write(header)
        f.write(pixel_data)
    
    print(f"Generated {output_path} for '{seed_text}'")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 nano_banana.py <seed_text> <output_path>")
        sys.exit(1)
    
    generate_tga(sys.argv[1], sys.argv[2])