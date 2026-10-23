"""Render TrafficGo's own geometric icon; requires Pillow. No external artwork."""
from pathlib import Path
import json
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
image = Image.new('RGB', (1024, 1024), '#007c78')
draw = ImageDraw.Draw(image)
draw.rounded_rectangle((190, 150, 834, 874), radius=190, fill='#006963')
draw.line([(350, 850), (350, 610), (680, 380), (680, 180)], fill='#40b3a1', width=80)
draw.polygon([(512, 235), (750, 735), (512, 620), (274, 735)], fill='white')
for x, color in [(405, '#2eab30'), (512, '#f1bf40'), (619, '#f18237')]:
    draw.ellipse((x-26, 810, x+26, 862), fill=color)
assets = root/'mobile/assets'
assets.mkdir(exist_ok=True)
image.save(assets/'trafficgo-icon.png')
icons = root/'mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset'
for entry in json.loads((icons/'Contents.json').read_text())['images']:
    if 'filename' in entry:
        size = round(float(entry['size'].split('x')[0])*float(entry['scale'].removesuffix('x')))
        image.resize((size, size), Image.Resampling.LANCZOS).save(icons/entry['filename'])
for folder, size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    image.resize((size,size),Image.Resampling.LANCZOS).save(root/f'mobile/android/app/src/main/res/mipmap-{folder}/ic_launcher.png')
for size in [192,512]:
    for name in [f'Icon-{size}.png',f'Icon-maskable-{size}.png']:
        image.resize((size,size),Image.Resampling.LANCZOS).save(root/'mobile/web/icons'/name)
image.resize((32,32),Image.Resampling.LANCZOS).save(root/'mobile/web/favicon.png')
