from PIL import Image, ImageDraw
L = "lookdev_render/"
W, H = 640, 360
def cell(path):
    im = Image.open(path).convert("RGB")
    if im.width > 2000:
        im = im.crop((int(im.width*0.09), 0, int(im.width*0.91), im.height))
    im.thumbnail((W, H)); return im
def sheet(out, rows):
    sh = Image.new("RGB", (3*W, len(rows)*(H+18)), (20,20,20)); d = ImageDraw.Draw(sh)
    for r,(items) in enumerate(rows):
        for c,(lab,p) in enumerate(items):
            if p is None: continue
            im = cell(p); sh.paste(im, (c*W, r*(H+18)+18)); d.text((c*W+4, r*(H+18)+2), lab, fill=(240,240,240))
    sh.save(L+out); print("wrote", out)
sheet("sheet_final_day.png", [[("ANTES: juego (Compatibility)", L+"before_day_game_compat.png"), ("REFERENCIA dia", L+"ref_day.jpg"), ("DESPUES: look-dev Forward+", L+"day_forward_plus.png")],
                             [("DESPUES: look-dev Compatibility", L+"day_filmic_e0.28_compat.png"), ("REFERENCIA atardecer", L+"ref_dusk.jpg"), ("DESPUES: atardecer Forward+", L+"dusk_forward_plus.png")]])
sheet("sheet_final_night.png", [[("ANTES: juego noche (Compatibility)", L+"before_night_game_compat.png"), ("REFERENCIA noche", L+"ref_night.jpg"), ("DESPUES: noche Forward+", L+"night_forward_plus.png")],
                               [("DESPUES: noche Compatibility", L+"night_filmic_e0.35_compat.png"), ("ANTES: ventisca (juego)", L+"before_blizzard_game_compat.png"), ("DESPUES: ventisca Forward+ (volumetrica)", L+"blizzard_forward_plus.png")]])
