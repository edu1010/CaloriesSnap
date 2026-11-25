"""Generates lib/data/local/ingredients_es.json.

Each ingredient groups its preparations (raw, boiled, fried, grilled...) so
the app can offer "arroz" -> crudo / hervido / frito. Values are per 100 g of
the food as eaten.

Nutrient values come from the official French table CIQUAL 2020 (ANSES,
CC BY 4.0, https://doi.org/10.5281/zenodo.4770202): see CIQUAL below, which
maps every variant to a CIQUAL food code. Energy is the EU Regulation
1169/2011 value of the table; when the table leaves it blank it is computed
with the same regulation's factors (protein 4, carbohydrate 4, fat 9, fibre 2,
polyols 2.4, alcohol 7, organic acids 3 kcal/g).

Home preparations the table does not list (fried rice, sauteed vegetables...)
are DERIVED: the CIQUAL cooked food plus a stated share of CIQUAL olive oil.
They are marked as estimates in the output. Variants with no CIQUAL food at all
keep the hand-written values in DATA and are marked "estimate".

Needs the CIQUAL table exported to CSV (UTF-8) at CIQUAL_CSV:

    python tool/build_ingredients_db.py
"""

import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "lib/data/local/ingredients_es.json"
CIQUAL_CSV = ROOT / "datasets/ciqual_2020/ciqual_2020_eng.csv"
SOURCE = ("Anses. 2020. Ciqual French food composition table "
          "(CC BY 4.0, doi:10.5281/zenodo.4770202)")
OLIVE_OIL = 17270

# (ingredient id, prep or English name of a kind) -> CIQUAL code, or
# (code, grams of olive oil per 100 g of the prepared food).
CIQUAL = {
    ("rice", "raw"): 9100, ("rice", "boiled"): 9104,
    ("rice", "fried"): (9104, 5),
    ("brown_rice", "raw"): 9102, ("brown_rice", "boiled"): 9103,
    ("pasta", "raw"): 9810, ("pasta", "boiled"): 9811,
    ("wholewheat_pasta", "raw"): 9870, ("wholewheat_pasta", "boiled"): 9871,
    ("noodles", "raw"): 9810, ("noodles", "boiled"): 9811,
    ("noodles", "fried"): (9811, 8),
    ("potato", "raw"): 4008, ("potato", "boiled"): 4003,
    ("potato", "fried"): 4032, ("potato", "baked"): 4002,
    ("potato", "mashed"): 4018,
    ("sweet_potato", "raw"): 4101, ("sweet_potato", "boiled"): 4102,
    ("sweet_potato", "fried"): (4102, 10),
    ("bread", "White bread"): 7001, ("bread", "Wholemeal bread"): 7110,
    ("bread", "Sliced bread"): 7200, ("bread", "toasted"): 7004,
    ("oats", "raw"): 9311, ("oats", "Oat porridge"): 9313,
    ("quinoa", "raw"): 9340, ("quinoa", "boiled"): 9341,
    ("couscous", "raw"): 9681, ("couscous", "cooked"): 9683,
    ("corn", "boiled"): 20049, ("corn", "canned"): 20066,
    ("chickpeas", "dried"): 20516, ("chickpeas", "cooked"): 20507,
    ("chickpeas", "canned"): 20532,
    ("lentils", "dried"): 20504, ("lentils", "cooked"): 20505,
    ("beans", "dried"): 20501, ("beans", "cooked"): 20502,
    ("peas", "raw"): 20072, ("peas", "boiled"): 20326,
    ("peas", "canned"): 20036,
    ("green_beans", "raw"): 20061, ("green_beans", "boiled"): 20320,
    ("green_beans", "sauteed"): (20320, 3),
    ("chicken_breast", "raw"): 36017, ("chicken_breast", "grilled"): 36018,
    ("chicken_breast", "boiled"): 36018, ("chicken_breast", "baked"): 36018,
    ("chicken_breast", "fried"): (36018, 4),
    ("chicken_breast", "breaded"): 36318,
    ("chicken_thigh", "raw"): 36002, ("chicken_thigh", "roasted"): 36004,
    ("chicken_thigh", "fried"): (36004, 4),
    ("roast_chicken", "roasted"): 36005, ("roast_chicken", "stewed"): 36031,
    ("roast_chicken", "fried"): (36005, 4),
    ("turkey_breast", "raw"): 36304, ("turkey_breast", "grilled"): 36306,
    ("beef_steak", "raw"): 6111, ("beef_steak", "grilled"): 6110,
    ("beef_steak", "fried"): (6110, 3), ("beef_steak", "stewed"): 6101,
    ("minced_beef", "raw"): 6256, ("minced_beef", "fried"): 6257,
    ("burger_patty", "raw"): 6254, ("burger_patty", "grilled"): 6255,
    ("pork_loin", "raw"): 28302, ("pork_loin", "grilled"): 28101,
    ("pork_loin", "fried"): (28101, 3),
    ("pork_ribs", "raw"): 28400, ("pork_ribs", "baked"): 28401,
    ("lamb_chops", "grilled"): 21512,
    ("sausage", "cooked"): 30134, ("sausage", "grilled"): 30011,
    ("sausage", "fried"): (30011, 3),
    ("chorizo", "cured"): 30316, ("chorizo", "fried"): (30316, 2),
    ("bacon", "raw"): 28720, ("bacon", "fried"): 28504,
    ("serrano_ham", "cured"): 28845, ("cooked_ham", "cooked"): 28900,
    ("egg", "raw"): 22000, ("egg", "boiled"): 22010, ("egg", "fried"): 22501,
    ("egg", "scrambled"): 22502, ("egg", "Omelette"): 22509,
    ("salmon", "raw"): 26036, ("salmon", "grilled"): 26229,
    ("salmon", "baked"): 26230, ("salmon", "smoked"): 26037,
    ("hake", "raw"): 26044, ("hake", "grilled"): 26120,
    ("hake", "battered"): 26030,
    ("cod", "raw"): 26043, ("cod", "baked"): 26023, ("cod", "battered"): 26030,
    ("tuna", "raw"): 26053, ("tuna", "grilled"): 26041,
    ("tuna", "Tuna in oil"): 26245, ("tuna", "Tuna in water"): 26039,
    ("sea_bream", "raw"): 26080, ("sea_bream", "grilled"): 27031,
    ("sea_bream", "baked"): 27031,
    ("sardines", "raw"): 26065, ("sardines", "grilled"): 26136,
    ("sardines", "Sardines in oil"): 26040,
    ("prawns", "raw"): 10021, ("prawns", "boiled"): 10007,
    ("prawns", "grilled"): 10007, ("prawns", "Garlic prawns"): (10007, 8),
    ("squid", "raw"): 10001, ("squid", "grilled"): 10084,
    ("squid", "battered"): 10002,
    ("octopus", "raw"): 10018, ("octopus", "boiled"): 10079,
    ("mussels", "steamed"): 10013,
    ("milk", "Whole milk"): 19023, ("milk", "Semi-skimmed milk"): 19041,
    ("milk", "Skimmed milk"): 19050,
    ("yogurt", "Plain yogurt"): 19593, ("yogurt", "Greek yogurt"): 19860,
    ("yogurt", "Low-fat yogurt"): 19594,
    ("yogurt", "Sweetened yogurt"): 19599,
    ("cheese", "Semi-cured cheese"): 12755, ("cheese", "Cured cheese"): 12100,
    ("cheese", "Mozzarella"): 19590, ("cheese", "Grated parmesan"): 12120,
    ("butter", "raw"): 16400, ("cream", "raw"): 19430,
    ("tomato", "raw"): 20047, ("tomato", "Tomato sauce"): 11107,
    ("lettuce", "raw"): 20031,
    ("onion", "raw"): 20034, ("onion", "fried"): (20035, 8),
    ("onion", "grilled"): 20322,
    ("pepper", "raw"): 20041, ("pepper", "roasted"): 20088,
    ("pepper", "fried"): (20088, 8),
    ("zucchini", "raw"): 20020, ("zucchini", "grilled"): 20313,
    ("zucchini", "sauteed"): (20021, 3),
    ("eggplant", "raw"): 20053, ("eggplant", "grilled"): 20300,
    ("eggplant", "fried"): (20002, 12),
    ("carrot", "raw"): 20009, ("carrot", "boiled"): 20306,
    ("broccoli", "raw"): 20057, ("broccoli", "boiled"): 20303,
    ("broccoli", "steamed"): 20304, ("broccoli", "sauteed"): (20303, 3),
    ("cauliflower", "raw"): 20016, ("cauliflower", "boiled"): 20017,
    ("spinach", "raw"): 20059, ("spinach", "boiled"): 20336,
    ("spinach", "sauteed"): (20336, 3),
    ("mushrooms", "raw"): 20056, ("mushrooms", "grilled"): 20125,
    ("mushrooms", "sauteed"): (20125, 4),
    ("cucumber", "raw"): 20019,
    ("asparagus", "raw"): 20279, ("asparagus", "canned"): 20076,
    ("asparagus", "grilled"): (20299, 2),
    ("avocado", "raw"): 13004, ("olives", "raw"): 13184,
    ("apple", "raw"): 13039, ("apple", "baked"): 13175,
    ("banana", "raw"): 13005,
    ("orange", "raw"): 13034, ("orange", "Fresh orange juice"): 2013,
    ("strawberries", "raw"): 13014, ("grapes", "raw"): 13112,
    ("pear", "raw"): 13037,
    ("peach", "raw"): 13043, ("peach", "Peach in syrup"): 13730,
    ("watermelon", "raw"): 13036,
    # Spanish "piel de sapo" is a honeydew-type melon, not a cantaloupe.
    ("melon", "raw"): 13742,
    ("pineapple", "raw"): 13002, ("pineapple", "Pineapple in syrup"): 13718,
    ("kiwi", "raw"): 13021, ("mango", "raw"): 13025,
    ("olive_oil", "raw"): 17270, ("sunflower_oil", "raw"): 17440,
    ("almonds", "raw"): 15041, ("almonds", "toasted"): 15042,
    ("walnuts", "raw"): 15005,
    ("peanuts", "toasted"): 15053, ("peanuts", "fried"): 15002,
    ("mayonnaise", "raw"): 11054, ("ketchup", "raw"): 11008,
    ("sugar", "raw"): 31016, ("honey", "raw"): 31008,
    ("chocolate", "Dark chocolate"): 31074,
    ("chocolate", "Milk chocolate"): 31004,
}

ENERGY = "Energy, Regulation EU No 1169/2011 (kcal/100g)"
FACTORS = {  # Regulation (EU) No 1169/2011, Annex XIV
    "Protein (g/100g)": 4, "Carbohydrate (g/100g)": 4, "Fat (g/100g)": 9,
    "Fibres (g/100g)": 2, "Polyols (g/100g)": 2.4, "Alcohol (g/100g)": 7,
    "Organic acids (g/100g)": 3,
}


def number(text):
    """CIQUAL cell -> float. '-' is unknown, 'traces' 0, '< x' half of x."""
    text = (text or "").strip().replace(",", ".")
    if text in ("", "-"):
        return None
    if text == "traces":
        return 0.0
    if text.startswith("<"):
        return float(text[1:].strip()) / 2
    return float(text)


def load_ciqual():
    if not CIQUAL_CSV.exists():
        raise SystemExit(
            f"Missing {CIQUAL_CSV}. Download 'Table Ciqual 2020_ENG_2020 07 "
            "07.xls' from https://zenodo.org/records/4770202 and export the "
            "sheet to CSV (UTF-8) at that path.")
    with CIQUAL_CSV.open(encoding="utf-8") as f:
        return {int(float(r["alim_code"])): r for r in csv.DictReader(f)}


def nutrients(row, code):
    out = {}
    for key, name in (("protein", "Protein (g/100g)"),
                      ("carbs", "Carbohydrate (g/100g)"),
                      ("fat", "Fat (g/100g)")):
        value = number(row[name])
        if value is None:
            raise SystemExit(f"CIQUAL {code} has no {name}")
        out[key] = value
    kcal = number(row[ENERGY])
    if kcal is None:
        kcal = sum((number(row[k]) or 0) * f for k, f in FACTORS.items())
    out["kcal"] = kcal
    return out


def from_ciqual(table, ref):
    if isinstance(ref, tuple):
        code, oil = ref
        base = nutrients(table[code], code)
        fat = nutrients(table[OLIVE_OIL], OLIVE_OIL)
        mixed = {k: base[k] * (100 - oil) / 100 + fat[k] * oil / 100
                 for k in base}
        return mixed, f"ciqual:{code}+oil{oil}"
    return nutrients(table[ref], ref), f"ciqual:{ref}"


def V(prep, kcal, protein, carbs, fat, grams=None, label_es=None,
      label_en=None, name_es=None, name_en=None):
    v = {"prep": prep, "kcal": kcal, "protein": protein, "carbs": carbs,
         "fat": fat}
    if grams:
        v["grams"] = list(grams)
    if label_es:
        v["labelEs"], v["labelEn"] = label_es, label_en
    if name_es:
        v["nameEs"], v["name"] = name_es, name_en
    return v


def C(label_es, label_en, name_es, name_en, kcal, protein, carbs, fat,
      grams=None):
    """A variant that is a kind rather than a cooking method (milk types)."""
    return V("custom", kcal, protein, carbs, fat, grams, label_es, label_en,
             name_es, name_en)


def I(id_, name, name_es, gender, category, grams, variants, default=None,
      aliases=()):
    return {"id": id_, "name": name, "nameEs": name_es, "gender": gender,
            "category": category, "aliases": list(aliases),
            "grams": list(grams),
            "default": default or variants[0]["prep"],
            "variants": variants}


DATA = [
    # --- Cereals and starches ---------------------------------------------
    I("rice", "Rice", "Arroz", "m", "cereal", (120, 180, 260), [
        V("raw", 354, 7.1, 78, 0.6, (50, 70, 100)),
        V("boiled", 130, 2.7, 28, 0.3),
        V("fried", 175, 3.5, 28, 5.5),
    ], default="boiled", aliases=["arroz blanco", "white rice"]),
    I("brown_rice", "Brown rice", "Arroz integral", "m", "cereal",
      (120, 180, 260), [
        V("raw", 350, 7.5, 72, 2.7, (50, 70, 100)),
        V("boiled", 112, 2.6, 23, 0.9),
    ], default="boiled"),
    I("pasta", "Pasta", "Pasta", "f", "cereal", (150, 220, 300), [
        V("raw", 360, 12.5, 72, 1.5, (60, 80, 110)),
        V("boiled", 158, 5.8, 31, 0.9),
    ], default="boiled",
      aliases=["macarrones", "espaguetis", "spaghetti", "tallarines",
               "penne", "fusilli", "macaroni"]),
    I("wholewheat_pasta", "Wholewheat pasta", "Pasta integral", "f", "cereal",
      (150, 220, 300), [
        V("raw", 348, 14, 66, 2.5, (60, 80, 110)),
        V("boiled", 124, 5.3, 26, 0.5),
    ], default="boiled"),
    I("noodles", "Noodles", "Fideos", "mp", "cereal", (150, 220, 300), [
        V("raw", 360, 12, 73, 1.5, (50, 70, 100)),
        V("boiled", 138, 4.5, 25, 2),
        V("fried", 230, 5, 30, 10),
    ], default="boiled", aliases=["noodles", "fideos chinos"]),
    I("potato", "Potato", "Patata", "f", "tuber", (100, 150, 250), [
        V("raw", 77, 2, 17, 0.1),
        V("boiled", 86, 1.7, 20, 0.1),
        V("fried", 290, 3.4, 36, 15, (80, 130, 200),
          name_es="Patatas fritas", name_en="French fries"),
        V("baked", 93, 2.5, 21, 0.1),
        V("mashed", 95, 2, 15, 3.5, (120, 180, 250)),
    ], default="boiled", aliases=["patatas", "papa", "papas", "potatoes"]),
    I("sweet_potato", "Sweet potato", "Boniato", "m", "tuber", (100, 150, 250), [
        V("raw", 86, 1.6, 20, 0.1),
        V("boiled", 76, 1.4, 18, 0.1),
        V("baked", 90, 2, 21, 0.2),
        V("fried", 230, 1.6, 28, 12),
    ], default="baked", aliases=["batata", "camote"]),
    I("bread", "Bread", "Pan", "m", "bread", (30, 60, 100), [
        C("Blanco", "White", "Pan blanco", "White bread", 265, 9, 49, 3.2),
        C("Integral", "Wholemeal", "Pan integral", "Wholemeal bread",
          250, 12, 41, 3.5),
        C("De molde", "Sliced", "Pan de molde", "Sliced bread", 265, 8, 47, 4,
          (25, 50, 75)),
        V("toasted", 313, 11, 58, 4, (25, 50, 75)),
    ], default="custom", aliases=["barra", "baguette", "tostada"]),
    I("oats", "Oats", "Copos de avena", "mp", "cereal", (30, 50, 80), [
        V("raw", 380, 13, 60, 7),
        C("En gachas (agua)", "Porridge (water)", "Gachas de avena",
          "Oat porridge", 70, 2.5, 12, 1.4, (150, 250, 350)),
    ], aliases=["avena", "oatmeal", "porridge"]),
    I("quinoa", "Quinoa", "Quinoa", "f", "cereal", (100, 160, 240), [
        V("raw", 368, 14, 64, 6, (40, 60, 90)),
        V("boiled", 120, 4.4, 21, 1.9),
    ], default="boiled"),
    I("couscous", "Couscous", "Cuscús", "m", "cereal", (100, 160, 240), [
        V("raw", 376, 12.8, 77, 0.6, (40, 60, 90)),
        V("cooked", 112, 3.8, 23, 0.2),
    ], default="cooked", aliases=["cous cous", "cuscus"]),
    I("corn", "Sweetcorn", "Maíz", "m", "vegetable", (50, 80, 120), [
        V("boiled", 96, 3.4, 21, 1.5),
        V("canned", 80, 2.6, 16, 1.2),
    ], default="canned", aliases=["maiz dulce", "mazorca", "corn"]),

    # --- Legumes -----------------------------------------------------------
    I("chickpeas", "Chickpeas", "Garbanzos", "mp", "legume", (120, 180, 250), [
        V("dried", 364, 19, 61, 6, (50, 70, 90)),
        V("cooked", 164, 8.9, 27, 2.6),
        V("canned", 139, 7.1, 22, 2.4),
    ], default="cooked", aliases=["garbanzo", "chickpea"]),
    I("lentils", "Lentils", "Lentejas", "fp", "legume", (120, 180, 250), [
        V("dried", 353, 25, 60, 1, (50, 70, 90)),
        V("cooked", 116, 9, 20, 0.4),
    ], default="cooked", aliases=["lenteja", "lentil"]),
    I("beans", "Beans", "Alubias", "fp", "legume", (120, 180, 250), [
        V("dried", 333, 23, 60, 0.8, (50, 70, 90)),
        V("cooked", 127, 8.7, 22.8, 0.5),
    ], default="cooked",
      aliases=["judias blancas", "frijoles", "habichuelas", "beans"]),
    I("peas", "Peas", "Guisantes", "mp", "vegetable", (60, 100, 150), [
        V("raw", 81, 5.4, 14, 0.4),
        V("boiled", 84, 5.4, 15, 0.2),
        V("canned", 68, 4.2, 12, 0.4),
    ], default="boiled", aliases=["guisante", "arvejas", "chicharos"]),
    I("green_beans", "Green beans", "Judías verdes", "fp", "vegetable",
      (100, 150, 220), [
        V("raw", 31, 1.8, 7, 0.2),
        V("boiled", 35, 1.9, 7.9, 0.3),
        V("sauteed", 60, 2, 7, 3),
    ], default="boiled", aliases=["judias", "vainas", "ejotes"]),

    # --- Meat ----------------------------------------------------------------
    I("chicken_breast", "Chicken breast", "Pechuga de pollo", "f", "meat",
      (100, 150, 200), [
        V("raw", 120, 22.5, 0, 2.6),
        V("grilled", 165, 31, 0, 3.6),
        V("boiled", 151, 29, 0, 3),
        V("baked", 165, 31, 0, 3.6),
        V("fried", 195, 30, 0, 8),
        V("breaded", 260, 18, 14, 15),
    ], default="grilled", aliases=["pollo", "pechuga", "chicken"]),
    I("chicken_thigh", "Chicken thigh", "Muslo de pollo", "m", "meat",
      (100, 150, 220), [
        V("raw", 177, 18, 0, 11),
        V("roasted", 229, 24, 0, 15),
        V("fried", 260, 26, 3, 16),
    ], default="roasted", aliases=["contramuslo", "muslos de pollo"]),
    I("roast_chicken", "Chicken", "Pollo", "m", "meat", (150, 250, 350), [
        V("roasted", 239, 27, 0, 14),
        V("stewed", 190, 25, 1, 9.5),
        V("fried", 260, 25, 6, 15),
    ], aliases=["pollo entero", "chicken"]),
    I("turkey_breast", "Turkey breast", "Pechuga de pavo", "f", "meat",
      (100, 150, 200), [
        V("raw", 105, 22, 0, 1.5),
        V("grilled", 147, 30, 0, 2),
    ], default="grilled", aliases=["pavo", "turkey"]),
    I("beef_steak", "Beef steak", "Filete de ternera", "m", "meat",
      (100, 150, 220), [
        V("raw", 130, 21, 0, 5),
        V("grilled", 175, 29, 0, 6.5),
        V("fried", 210, 28, 0, 11),
        V("stewed", 190, 27, 0, 9),
    ], default="grilled",
      aliases=["ternera", "filete", "bistec", "entrecot", "beef", "steak",
               "carne de ternera"]),
    I("minced_beef", "Minced beef", "Carne picada", "f", "meat",
      (80, 125, 180), [
        V("raw", 250, 17, 0, 20),
        V("fried", 270, 26, 0, 18),
    ], default="fried", aliases=["picada", "ground beef", "minced meat"]),
    I("burger_patty", "Beef burger", "Hamburguesa de ternera", "f", "meat",
      (90, 125, 180), [
        V("raw", 230, 18, 1, 17),
        V("grilled", 260, 25, 0, 17),
    ], default="grilled", aliases=["hamburguesa", "burger patty"]),
    I("pork_loin", "Pork loin", "Lomo de cerdo", "m", "meat", (100, 150, 200), [
        V("raw", 145, 21, 0, 6.5),
        V("grilled", 190, 29, 0, 8),
        V("fried", 230, 27, 0, 13),
    ], default="grilled", aliases=["lomo", "cerdo", "pork"]),
    I("pork_ribs", "Pork ribs", "Costillas de cerdo", "fp", "meat",
      (150, 250, 350), [
        V("raw", 277, 16, 0, 23),
        V("baked", 320, 24, 0, 24),
    ], default="baked", aliases=["costillas", "ribs", "costilla"]),
    I("lamb_chops", "Lamb chops", "Chuletas de cordero", "fp", "meat",
      (100, 160, 240), [
        V("grilled", 290, 24, 0, 21),
    ], default="grilled", aliases=["cordero", "chuletillas", "lamb"]),
    I("sausage", "Sausage", "Salchicha", "f", "meat", (50, 100, 150), [
        V("cooked", 280, 12, 2, 25),
        V("fried", 310, 13, 2, 27),
        V("grilled", 290, 13, 2, 26),
    ], default="grilled", aliases=["salchichas", "frankfurt", "sausages"]),
    I("chorizo", "Chorizo", "Chorizo", "m", "meat", (20, 40, 60), [
        V("cured", 455, 24, 2, 38),
        V("fried", 480, 24, 2, 41),
    ]),
    I("bacon", "Bacon", "Bacon", "m", "meat", (15, 30, 50), [
        V("raw", 400, 13, 0, 38),
        V("fried", 540, 37, 1.4, 42),
    ], default="fried", aliases=["beicon", "panceta", "tocino"]),
    I("serrano_ham", "Cured ham", "Jamón serrano", "m", "meat", (20, 40, 70), [
        V("cured", 241, 31, 0, 13),
    ], aliases=["jamon", "jamon iberico", "ham"]),
    I("cooked_ham", "Cooked ham", "Jamón cocido", "m", "meat", (20, 40, 70), [
        V("cooked", 110, 18, 1.5, 3.5),
    ], aliases=["jamon york", "york"]),
    I("egg", "Egg", "Huevo", "m", "egg", (50, 60, 120), [
        V("raw", 143, 12.6, 0.7, 9.5),
        V("boiled", 155, 12.6, 1.1, 10.6),
        V("fried", 196, 13.6, 0.8, 15),
        V("scrambled", 170, 11, 1.6, 13),
        C("En tortilla francesa", "Omelette", "Tortilla francesa",
          "Omelette", 175, 11, 1, 14, (60, 120, 180)),
    ], default="boiled", aliases=["huevos", "eggs"]),

    # --- Fish and seafood ----------------------------------------------------
    I("salmon", "Salmon", "Salmón", "m", "fish", (100, 150, 200), [
        V("raw", 208, 20, 0, 13),
        V("grilled", 206, 22, 0, 12.5),
        V("baked", 206, 22, 0, 12.5),
        V("smoked", 117, 18, 0, 4.3, (30, 50, 80)),
    ], default="grilled", aliases=["salmon"]),
    I("hake", "Hake", "Merluza", "f", "fish", (100, 150, 200), [
        V("raw", 86, 17, 0, 1.8),
        V("grilled", 100, 20, 0, 2),
        V("steamed", 90, 18, 0, 1.9),
        V("battered", 195, 14, 9, 11),
    ], default="grilled", aliases=["pescadilla", "hake"]),
    I("cod", "Cod", "Bacalao", "m", "fish", (100, 150, 200), [
        V("raw", 82, 18, 0, 0.7),
        V("baked", 105, 23, 0, 0.9),
        V("battered", 210, 15, 10, 12),
    ], default="baked", aliases=["cod"]),
    I("tuna", "Tuna", "Atún", "m", "fish", (50, 80, 150), [
        V("raw", 108, 24, 0, 1, (100, 150, 200)),
        V("grilled", 130, 28, 0, 1.3, (100, 150, 200)),
        C("En lata, en aceite", "Canned in oil", "Atún en aceite",
          "Tuna in oil", 198, 29, 0, 8.2),
        C("En lata, al natural", "Canned in water", "Atún al natural",
          "Tuna in water", 116, 26, 0, 1),
    ], default="custom", aliases=["atun", "bonito", "tuna"]),
    I("sea_bream", "Sea bream", "Dorada", "f", "fish", (120, 180, 250), [
        V("raw", 100, 20, 0, 2),
        V("grilled", 125, 24, 0, 3),
        V("baked", 125, 24, 0, 3),
    ], default="baked", aliases=["lubina", "sea bass", "dorada"]),
    I("sardines", "Sardines", "Sardinas", "fp", "fish", (60, 100, 150), [
        V("raw", 165, 20, 0, 9),
        V("grilled", 185, 24, 0, 10),
        C("En lata, en aceite", "Canned in oil", "Sardinas en aceite",
          "Sardines in oil", 208, 25, 0, 11.5, (50, 85, 120)),
    ], default="grilled", aliases=["sardina", "boquerones", "sardines"]),
    I("prawns", "Prawns", "Gambas", "fp", "seafood", (60, 100, 150), [
        V("raw", 85, 20, 0, 0.5),
        V("boiled", 99, 24, 0.2, 0.3),
        V("grilled", 105, 24, 0.2, 1),
        C("Al ajillo", "Garlic (in oil)", "Gambas al ajillo",
          "Garlic prawns", 180, 18, 1, 12),
    ], default="grilled", aliases=["langostinos", "camarones", "shrimp"]),
    I("squid", "Squid", "Calamar", "m", "seafood", (80, 120, 180), [
        V("raw", 92, 15.6, 3, 1.4),
        V("grilled", 110, 18, 3, 2),
        V("battered", 230, 13, 15, 13),
    ], default="grilled",
      aliases=["calamares", "sepia", "chipirones", "squid"]),
    I("octopus", "Octopus", "Pulpo", "m", "seafood", (80, 130, 200), [
        V("raw", 82, 15, 2.2, 1),
        V("boiled", 164, 30, 4.4, 2),
    ], default="boiled", aliases=["octopus"]),
    I("mussels", "Mussels", "Mejillones", "mp", "seafood", (80, 130, 200), [
        V("steamed", 172, 24, 7, 4.5),
    ], aliases=["mejillon", "mussels"]),

    # --- Dairy ----------------------------------------------------------------
    I("milk", "Milk", "Leche", "f", "dairy", (125, 200, 250), [
        C("Entera", "Whole", "Leche entera", "Whole milk", 64, 3.2, 4.7, 3.6),
        C("Semidesnatada", "Semi-skimmed", "Leche semidesnatada",
          "Semi-skimmed milk", 46, 3.3, 4.8, 1.6),
        C("Desnatada", "Skimmed", "Leche desnatada", "Skimmed milk",
          35, 3.4, 4.9, 0.2),
    ], aliases=["milk"]),
    I("yogurt", "Yogurt", "Yogur", "m", "dairy", (125, 125, 250), [
        C("Natural", "Plain", "Yogur natural", "Plain yogurt",
          61, 3.5, 4.7, 3.3),
        C("Griego", "Greek", "Yogur griego", "Greek yogurt", 115, 6, 4, 9),
        C("Desnatado", "Low-fat", "Yogur desnatado", "Low-fat yogurt",
          40, 4.3, 5.5, 0.1),
        C("Azucarado", "Sweetened", "Yogur azucarado", "Sweetened yogurt",
          90, 3.3, 14, 2.7),
    ], aliases=["yogurt", "yoghurt"]),
    I("cheese", "Cheese", "Queso", "m", "dairy", (20, 40, 70), [
        C("Fresco", "Fresh", "Queso fresco", "Fresh cheese", 175, 12, 3, 13,
          (30, 60, 100)),
        C("Semicurado", "Semi-cured", "Queso semicurado",
          "Semi-cured cheese", 360, 24, 0.5, 29),
        C("Curado", "Cured", "Queso curado", "Cured cheese", 400, 26, 0.5, 33),
        C("Mozzarella", "Mozzarella", "Mozzarella", "Mozzarella",
          280, 22, 2, 20, (30, 60, 125)),
        C("Rallado (parmesano)", "Grated parmesan", "Queso parmesano rallado",
          "Grated parmesan", 431, 38, 4, 29, (5, 10, 20)),
    ], default="custom", aliases=["cheese", "manchego"]),
    I("butter", "Butter", "Mantequilla", "f", "fat", (5, 10, 20), [
        V("raw", 717, 0.9, 0.1, 81, label_es="Natural", label_en="Plain",
          name_es="Mantequilla", name_en="Butter"),
    ], aliases=["butter"]),
    I("cream", "Cooking cream", "Nata para cocinar", "f", "dairy",
      (30, 50, 100), [
        V("raw", 195, 2.5, 3.5, 18, label_es="Natural", label_en="Plain",
          name_es="Nata para cocinar", name_en="Cooking cream"),
    ], aliases=["nata", "cream"]),

    # --- Vegetables -------------------------------------------------------------
    I("tomato", "Tomato", "Tomate", "m", "vegetable", (80, 120, 200), [
        V("raw", 18, 0.9, 3.9, 0.2),
        V("roasted", 30, 1, 4.5, 1),
        C("Frito (salsa)", "Tomato sauce", "Tomate frito", "Tomato sauce",
          80, 1.5, 9, 4, (30, 60, 100)),
    ], aliases=["tomates", "tomato"]),
    I("lettuce", "Lettuce", "Lechuga", "f", "vegetable", (30, 60, 100), [
        V("raw", 15, 1.4, 2.9, 0.2),
    ], aliases=["ensalada verde", "lettuce", "canonigos", "rucula"]),
    I("onion", "Onion", "Cebolla", "f", "vegetable", (30, 60, 100), [
        V("raw", 40, 1.1, 9.3, 0.1),
        V("fried", 130, 1.3, 10, 9.5),
        V("grilled", 45, 1.2, 10, 0.2),
    ], aliases=["onion"]),
    I("pepper", "Pepper", "Pimiento", "m", "vegetable", (50, 100, 150), [
        V("raw", 26, 1, 6, 0.3),
        V("roasted", 40, 1, 6, 1.5),
        V("fried", 120, 1, 6, 10),
    ], aliases=["pimientos", "bell pepper"]),
    I("zucchini", "Courgette", "Calabacín", "m", "vegetable", (80, 150, 220), [
        V("raw", 17, 1.2, 3.1, 0.3),
        V("grilled", 30, 1.5, 3.5, 1),
        V("sauteed", 50, 1.2, 3.5, 3.5),
    ], default="grilled", aliases=["calabacin", "zucchini"]),
    I("eggplant", "Aubergine", "Berenjena", "f", "vegetable", (80, 150, 220), [
        V("raw", 25, 1, 6, 0.2),
        V("grilled", 40, 1, 7, 1),
        V("fried", 150, 1.2, 8, 13),
    ], default="grilled", aliases=["eggplant", "berenjenas"]),
    I("carrot", "Carrot", "Zanahoria", "f", "vegetable", (50, 80, 120), [
        V("raw", 41, 0.9, 9.6, 0.2),
        V("boiled", 35, 0.8, 8.2, 0.2),
    ], aliases=["zanahorias", "carrot"]),
    I("broccoli", "Broccoli", "Brócoli", "m", "vegetable", (80, 150, 220), [
        V("raw", 34, 2.8, 7, 0.4),
        V("boiled", 35, 2.4, 7.2, 0.4),
        V("steamed", 35, 2.4, 7.2, 0.4),
        V("sauteed", 60, 2.6, 7, 3.5),
    ], default="boiled", aliases=["brocoli", "broccoli"]),
    I("cauliflower", "Cauliflower", "Coliflor", "f", "vegetable",
      (80, 150, 220), [
        V("raw", 25, 1.9, 5, 0.3),
        V("boiled", 23, 1.8, 4.1, 0.5),
    ], default="boiled"),
    I("spinach", "Spinach", "Espinacas", "fp", "vegetable", (60, 120, 200), [
        V("raw", 23, 2.9, 3.6, 0.4),
        V("boiled", 23, 3, 3.8, 0.3),
        V("sauteed", 55, 3, 4, 3.5),
    ], default="sauteed", aliases=["espinaca", "acelgas", "spinach"]),
    I("mushrooms", "Mushrooms", "Champiñones", "mp", "vegetable",
      (60, 100, 150), [
        V("raw", 22, 3.1, 3.3, 0.3),
        V("grilled", 28, 3.5, 4, 0.5),
        V("sauteed", 60, 3.5, 4, 4.5),
    ], default="sauteed", aliases=["champinon", "setas", "mushrooms"]),
    I("cucumber", "Cucumber", "Pepino", "m", "vegetable", (50, 100, 150), [
        V("raw", 15, 0.7, 3.6, 0.1),
    ]),
    I("asparagus", "Asparagus", "Espárragos", "mp", "vegetable",
      (60, 100, 150), [
        V("raw", 20, 2.2, 3.9, 0.1),
        V("grilled", 30, 2.4, 4, 1),
        V("canned", 20, 1.8, 2.5, 0.3),
    ], default="grilled", aliases=["esparrago", "trigueros", "asparagus"]),
    I("avocado", "Avocado", "Aguacate", "m", "fruit", (50, 80, 150), [
        V("raw", 160, 2, 8.5, 14.7),
    ], aliases=["guacamole", "avocado"]),
    I("olives", "Olives", "Aceitunas", "fp", "vegetable", (15, 30, 50), [
        V("raw", 145, 1, 3.8, 15, label_es="Aliñadas", label_en="Cured",
          name_es="Aceitunas", name_en="Olives"),
    ], aliases=["aceituna", "olivas", "olives"]),

    # --- Fruit -------------------------------------------------------------------
    I("apple", "Apple", "Manzana", "f", "fruit", (120, 180, 220), [
        V("raw", 52, 0.3, 14, 0.2),
        V("baked", 70, 0.4, 18, 0.2),
    ]),
    I("banana", "Banana", "Plátano", "m", "fruit", (90, 120, 150), [
        V("raw", 89, 1.1, 23, 0.3),
    ], aliases=["platano", "banana"]),
    I("orange", "Orange", "Naranja", "f", "fruit", (130, 180, 230), [
        V("raw", 47, 0.9, 12, 0.1),
        C("En zumo natural", "Fresh juice", "Zumo de naranja natural",
          "Fresh orange juice", 45, 0.7, 10, 0.2, (150, 200, 300)),
    ], aliases=["mandarina", "orange"]),
    I("strawberries", "Strawberries", "Fresas", "fp", "fruit", (100, 150, 250), [
        V("raw", 32, 0.7, 7.7, 0.3),
    ], aliases=["fresa", "freson", "strawberry"]),
    I("grapes", "Grapes", "Uvas", "fp", "fruit", (80, 120, 200), [
        V("raw", 69, 0.7, 18, 0.2),
    ], aliases=["uva", "grapes"]),
    I("pear", "Pear", "Pera", "f", "fruit", (120, 170, 220), [
        V("raw", 57, 0.4, 15, 0.1),
    ]),
    I("peach", "Peach", "Melocotón", "m", "fruit", (100, 150, 200), [
        V("raw", 39, 0.9, 10, 0.3),
        C("En almíbar", "In syrup", "Melocotón en almíbar",
          "Peach in syrup", 74, 0.5, 19, 0.1),
    ], aliases=["melocoton", "nectarina", "peach"]),
    I("watermelon", "Watermelon", "Sandía", "f", "fruit", (200, 300, 450), [
        V("raw", 30, 0.6, 7.6, 0.2),
    ], aliases=["sandia"]),
    I("melon", "Melon", "Melón", "m", "fruit", (150, 250, 400), [
        V("raw", 34, 0.8, 8, 0.2),
    ], aliases=["melon"]),
    I("pineapple", "Pineapple", "Piña", "f", "fruit", (100, 150, 250), [
        V("raw", 50, 0.5, 13, 0.1),
        C("En almíbar", "In syrup", "Piña en almíbar", "Pineapple in syrup",
          60, 0.4, 16, 0.1),
    ], aliases=["pina", "pineapple"]),
    I("kiwi", "Kiwi", "Kiwi", "m", "fruit", (70, 90, 150), [
        V("raw", 61, 1.1, 15, 0.5),
    ]),
    I("mango", "Mango", "Mango", "m", "fruit", (100, 150, 250), [
        V("raw", 60, 0.8, 15, 0.4),
    ]),

    # --- Fats, nuts, sauces and sweet extras ------------------------------------
    I("olive_oil", "Olive oil", "Aceite de oliva", "m", "fat", (5, 10, 15), [
        V("raw", 884, 0, 0, 100, label_es="Natural", label_en="Plain",
          name_es="Aceite de oliva", name_en="Olive oil"),
    ], aliases=["aceite", "aove", "oil"]),
    I("sunflower_oil", "Sunflower oil", "Aceite de girasol", "m", "fat",
      (5, 10, 15), [
        V("raw", 884, 0, 0, 100, label_es="Natural", label_en="Plain",
          name_es="Aceite de girasol", name_en="Sunflower oil"),
    ]),
    I("almonds", "Almonds", "Almendras", "fp", "nuts", (15, 30, 50), [
        V("raw", 579, 21, 22, 50),
        V("toasted", 598, 21, 21, 53),
        V("fried", 620, 20, 18, 56),
    ], aliases=["almendra", "almonds"]),
    I("walnuts", "Walnuts", "Nueces", "fp", "nuts", (15, 30, 50), [
        V("raw", 654, 15, 14, 65),
    ], aliases=["nuez", "walnuts"]),
    I("peanuts", "Peanuts", "Cacahuetes", "mp", "nuts", (15, 30, 50), [
        V("toasted", 585, 24, 21, 50),
        V("fried", 600, 25, 17, 53),
    ], aliases=["cacahuete", "mani", "peanuts"]),
    I("mayonnaise", "Mayonnaise", "Mayonesa", "f", "sauce", (10, 20, 30), [
        V("raw", 680, 1, 1, 75, label_es="Normal", label_en="Regular",
          name_es="Mayonesa", name_en="Mayonnaise"),
        C("Alioli", "Aioli", "Alioli", "Aioli", 700, 1, 2, 77),
    ], default="raw", aliases=["mahonesa", "mayo"]),
    I("ketchup", "Ketchup", "Kétchup", "m", "sauce", (10, 20, 30), [
        V("raw", 112, 1.3, 26, 0.2, label_es="Normal", label_en="Regular",
          name_es="Kétchup", name_en="Ketchup"),
    ], aliases=["ketchup", "catsup"]),
    I("sugar", "Sugar", "Azúcar", "m", "sweet", (5, 10, 20), [
        V("raw", 400, 0, 100, 0, label_es="Blanco", label_en="White",
          name_es="Azúcar", name_en="Sugar"),
    ], aliases=["azucar", "sugar"]),
    I("honey", "Honey", "Miel", "f", "sweet", (10, 20, 30), [
        V("raw", 304, 0.3, 82, 0, label_es="Natural", label_en="Plain",
          name_es="Miel", name_en="Honey"),
    ]),
    I("chocolate", "Chocolate", "Chocolate", "m", "sweet", (10, 20, 40), [
        C("Negro 70 %", "Dark 70%", "Chocolate negro", "Dark chocolate",
          600, 7.8, 46, 43),
        C("Con leche", "Milk", "Chocolate con leche", "Milk chocolate",
          535, 7.6, 59, 30),
    ]),
]


def main():
    ids = [item["id"] for item in DATA]
    assert len(ids) == len(set(ids)), "duplicate ingredient id"
    table = load_ciqual()
    used = set()
    report = []
    for item in DATA:
        preps = [v["prep"] for v in item["variants"] if v["prep"] != "custom"]
        assert len(preps) == len(set(preps)), item["id"]
        assert any(v["prep"] == item["default"] for v in item["variants"]),             item["id"]
        for v in item["variants"]:
            key = (item["id"],
                   v["prep"] if v["prep"] != "custom" else v["name"])
            ref = CIQUAL.get(key)
            if ref is None:
                # Hand-written value: energy must roughly match the macros.
                atwater = 4 * v["protein"] + 4 * v["carbs"] + 9 * v["fat"]
                assert abs(atwater - v["kcal"]) <= max(25, 0.15 * v["kcal"]),                     (key, v["kcal"], round(atwater))
                v["src"] = "estimate"
                report.append((key, v["kcal"], v["kcal"], "estimate"))
                continue
            used.add(key)
            values, src = from_ciqual(table, ref)
            report.append((key, v["kcal"], round(values["kcal"]), src))
            v["kcal"] = round(values["kcal"])
            for macro in ("protein", "carbs", "fat"):
                v[macro] = round(values[macro], 1)
            v["src"] = src
    unknown = set(CIQUAL) - used
    assert not unknown, f"mapping keys without a variant: {sorted(unknown)}"

    payload = {"source": SOURCE, "ingredients": DATA}
    text = json.dumps(payload, ensure_ascii=False, indent=1)
    OUT.write_text(text + "\n", encoding="utf-8")
    official = sum(1 for r in report if r[3].startswith("ciqual") and "+" not in r[3])
    derived = sum(1 for r in report if "+oil" in r[3])
    print(f"{len(DATA)} ingredients, {len(report)} variants: {official} CIQUAL, "
          f"{derived} CIQUAL + oil, {len(report) - official - derived} estimate"
          f" -> {OUT}")
    for key, old, new, src in report:
        if src == "estimate" or abs(old - new) >= max(15, 0.15 * old):
            print(f"  {key[0]:>16} {key[1]:<22} {old:>4} -> {new:>4}  {src}")


if __name__ == "__main__":
    main()
