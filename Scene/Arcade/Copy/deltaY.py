import os
from PIL import Image

def move_top_strip_to_bottom(img: Image.Image, strip_h: int = 10) -> Image.Image:
    """Move the top strip (strip_h pixels tall) to the bottom; keep size unchanged."""
    w, h = img.size
    if h <= 0 or w <= 0:
        return img.copy()

    # Clamp strip height in case image is shorter than strip_h
    strip_h = max(0, min(strip_h, h))
    if strip_h == 0:
        return img.copy()

    # Crop regions
    top = img.crop((0, 0, w, strip_h))
    rest = img.crop((0, strip_h, w, h))

    # Create output and paste
    out = Image.new(img.mode, (w, h))
    out.paste(rest, (0, 0))
    out.paste(top, (0, h - strip_h))
    return out

def process_folder(input_dir: str, output_dir: str, strip_h: int = 10) -> None:
    os.makedirs(output_dir, exist_ok=True)

    for name in os.listdir(input_dir):
        if not name.lower().endswith(".png"):
            continue

        in_path = os.path.join(input_dir, name)
        out_path = os.path.join(output_dir, name)

        try:
            with Image.open(in_path) as img:
                # 保留透明通道等信息：尽量不强转模式，只按原 mode 新建
                out = move_top_strip_to_bottom(img, strip_h=strip_h)

                # 尽量保留 PNG 的信息；如需可保留原 info，但一般没必要
                out.save(out_path, format="PNG")
                print(f"OK: {name} -> {out_path}")
        except Exception as e:
            print(f"FAIL: {name} ({e})")

if __name__ == "__main__":
    # 以“脚本所在目录”为工作目录更稳
    base_dir = os.path.dirname(os.path.abspath(__file__))
    input_dir = base_dir
    output_dir = os.path.join(base_dir, "output_png")

    process_folder(input_dir, output_dir, strip_h=41)
    print("Done.")
