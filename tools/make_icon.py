"""从鲸鱼娘立绘生成 Windows 多尺寸 .ico 图标。

用法：
    python make_icon.py <源图.png> <输出.ico> [边距比例=0.06]

依赖 Pillow（hermes 的 venv 里自带）。
"""
import sys
from PIL import Image

SIZES = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (24, 24), (16, 16)]


def build(src: str, out: str, margin_ratio: float = 0.06) -> None:
    im = Image.open(src).convert("RGBA")

    # 1) 裁掉四周全透明的边
    bbox = im.split()[3].getbbox()
    if bbox:
        im = im.crop(bbox)

    # 2) 补成正方形（透明底）
    side = max(im.size)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.paste(im, ((side - im.width) // 2, (side - im.height) // 2), im)

    # 3) 留一点边距，免得贴边太满
    m = int(side * margin_ratio)
    inner = square.resize((max(1, side - 2 * m), max(1, side - 2 * m)), Image.LANCZOS)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(inner, (m, m), inner)

    # 4) 输出多尺寸 ico（PIL 会写入标准 DIB 条目，Windows 各尺寸都认）
    canvas.save(out, format="ICO", sizes=SIZES)
    print(f"  已生成: {out}")
    print(f"  源图: {im.width}x{im.height} -> 正方形 {side}px，边距 {m}px")
    print(f"  尺寸: {', '.join(f'{w}x{h}' for w, h in SIZES)}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    build(sys.argv[1], sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else 0.06)
