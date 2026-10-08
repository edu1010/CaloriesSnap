"""Builds lib/data/local/common_foods_es.json.

Everyday foods, sandwiches and ready meals common in Spain that the on-device
vision model names but the classifier tables do not cover. Energy values are
rounded typical figures from generic food-composition tables (BEDCA / USDA
style averages); they are estimates for logging, not label data.

Rows: (name, nameEs, kcal/100 g, small g, medium g, large g, category)
"""
import json
from pathlib import Path

ROWS = [
    # Generic fallbacks for when the model names a food without detail
    ("Cheese", "Queso", 350, 20, 40, 70, "dairy"),
    ("Chicken", "Pollo", 190, 90, 140, 220, "meat"),
    ("Fish", "Pescado", 130, 100, 150, 220, "fish"),
    ("Meat", "Carne", 220, 90, 140, 220, "meat"),
    ("Pork", "Cerdo", 240, 90, 140, 220, "meat"),
    ("Beef", "Ternera", 220, 90, 140, 220, "meat"),
    ("Ham", "Jamón", 180, 20, 40, 80, "meat"),
    ("Vegetables", "Verduras", 50, 80, 150, 250, "vegetable"),
    ("Lettuce", "Lechuga", 15, 30, 60, 100, "vegetable"),
    ("Mushrooms", "Champiñones", 30, 50, 100, 180, "vegetable"),
    ("Zucchini", "Calabacín", 20, 80, 150, 250, "vegetable"),
    ("Eggplant", "Berenjena", 30, 80, 150, 250, "vegetable"),
    ("Peas", "Guisantes", 80, 60, 100, 180, "vegetable"),
    ("Green beans", "Judías verdes", 35, 80, 150, 250, "vegetable"),
    ("Asparagus", "Espárragos", 22, 60, 100, 180, "vegetable"),
    ("Legumes", "Legumbres", 125, 150, 250, 350, "stew"),
    ("Stew", "Guiso", 130, 200, 300, 400, "stew"),
    ("Soup", "Sopa", 50, 200, 300, 400, "soup"),
    ("Baguette sandwich", "Bocadillo", 260, 120, 180, 250, "sandwich"),
    ("Sauce", "Salsa", 120, 15, 30, 60, "sauce"),
    ("Oil", "Aceite", 884, 5, 10, 20, "fat"),
    ("Sugar", "Azúcar", 387, 5, 10, 20, "sauce"),
    ("Fruit", "Fruta", 55, 100, 150, 250, "fruit"),
    ("Cake", "Tarta", 350, 70, 110, 160, "dessert"),
    ("Milk", "Leche", 60, 150, 250, 350, "drink"),
    ("Water", "Agua", 0, 200, 330, 500, "drink"),
    ("Coffee", "Café", 2, 40, 100, 200, "drink"),
    ("Tea", "Té", 1, 150, 250, 350, "drink"),
    ("Juice", "Zumo", 45, 150, 250, 350, "drink"),
    ("Soft drink", "Refresco", 40, 200, 330, 500, "drink"),
    ("Wine", "Vino", 85, 100, 150, 250, "drink"),
    # Breads and bakery
    ("Baguette bread", "Pan de barra", 270, 40, 80, 130, "bread"),
    ("Sliced bread", "Pan de molde", 260, 30, 60, 90, "bread"),
    ("Whole wheat bread", "Pan integral", 245, 40, 70, 110, "bread"),
    ("Toast", "Tostada", 290, 25, 50, 80, "bread"),
    ("Burger bun", "Pan de hamburguesa", 280, 50, 65, 90, "bread"),
    ("Pita bread", "Pan de pita", 275, 40, 60, 90, "bread"),
    ("Croissant", "Cruasán", 406, 45, 65, 90, "bakery"),
    ("Muffin", "Magdalena", 390, 30, 60, 110, "bakery"),
    ("Sponge cake", "Bizcocho", 350, 50, 80, 120, "bakery"),
    ("Cookies", "Galletas", 470, 15, 30, 60, "bakery"),
    ("Doughnut", "Dónut", 420, 50, 60, 80, "bakery"),
    ("Napolitana pastry", "Napolitana de chocolate", 420, 60, 90, 120, "bakery"),
    ("Ensaimada", "Ensaimada", 430, 50, 80, 120, "bakery"),
    ("Breakfast cereal", "Cereales de desayuno", 375, 30, 40, 60, "bakery"),
    # Sandwiches (whole)
    ("Ham sandwich baguette", "Bocadillo de jamón", 255, 120, 180, 250, "sandwich"),
    ("Pork loin sandwich", "Bocadillo de lomo", 260, 130, 200, 270, "sandwich"),
    ("Pork loin and cheese sandwich", "Bocadillo de lomo con queso", 280, 140, 210, 280, "sandwich"),
    ("Spanish omelette sandwich", "Bocadillo de tortilla", 225, 150, 220, 300, "sandwich"),
    ("Chorizo sandwich", "Bocadillo de chorizo", 330, 110, 160, 230, "sandwich"),
    ("Tuna sandwich baguette", "Bocadillo de atún", 240, 130, 190, 260, "sandwich"),
    ("Cheese sandwich baguette", "Bocadillo de queso", 300, 110, 160, 230, "sandwich"),
    ("Chicken sandwich baguette", "Bocadillo de pollo", 230, 140, 210, 290, "sandwich"),
    ("Bacon sandwich baguette", "Bocadillo de beicon", 310, 120, 180, 250, "sandwich"),
    ("Ham and cheese toastie", "Sándwich mixto", 280, 90, 130, 180, "sandwich"),
    ("Vegetable sandwich", "Sándwich vegetal", 200, 120, 170, 230, "sandwich"),
    ("Kebab wrap", "Kebab", 215, 200, 320, 420, "sandwich"),
    ("Chicken wrap", "Wrap de pollo", 210, 150, 220, 300, "sandwich"),
    ("Montadito", "Montadito", 260, 40, 60, 90, "sandwich"),
    ("Pincho", "Pincho", 240, 50, 80, 120, "sandwich"),
    # Cured meats and cheese
    ("Cooked ham", "Jamón cocido", 110, 20, 40, 80, "meat"),
    ("Chorizo", "Chorizo", 455, 15, 30, 60, "meat"),
    ("Salchichon", "Salchichón", 440, 15, 30, 60, "meat"),
    ("Cured pork loin", "Lomo embuchado", 240, 15, 30, 60, "meat"),
    ("Bacon", "Beicon", 420, 15, 30, 60, "meat"),
    ("Sausage", "Salchicha", 290, 40, 80, 160, "meat"),
    ("Blood sausage", "Morcilla", 380, 40, 80, 130, "meat"),
    ("Fuet", "Fuet", 460, 15, 30, 60, "meat"),
    ("Mortadella", "Mortadela", 310, 15, 30, 60, "meat"),
    ("Manchego cheese", "Queso manchego", 400, 20, 40, 70, "dairy"),
    ("Fresh cheese", "Queso fresco", 175, 40, 70, 120, "dairy"),
    ("Mozzarella", "Mozzarella", 280, 30, 60, 125, "dairy"),
    ("Cheese slice", "Queso en lonchas", 320, 20, 40, 60, "dairy"),
    ("Cream cheese", "Queso crema", 250, 15, 30, 60, "dairy"),
    ("Goat cheese", "Queso de cabra", 320, 20, 40, 70, "dairy"),
    # Meat, fish and eggs
    ("Grilled pork loin", "Lomo a la plancha", 200, 80, 130, 200, "meat"),
    ("Breaded chicken", "Pollo empanado", 260, 90, 140, 200, "meat"),
    ("Roast chicken", "Pollo asado", 215, 120, 180, 280, "meat"),
    ("Fried chicken", "Pollo frito", 270, 100, 150, 240, "meat"),
    ("Entrecote", "Entrecot", 260, 150, 250, 350, "meat"),
    ("Lamb chops", "Chuletas de cordero", 290, 100, 160, 240, "meat"),
    ("Beef burger patty", "Hamburguesa de ternera", 250, 80, 120, 180, "meat"),
    ("Minced meat", "Carne picada", 240, 80, 130, 200, "meat"),
    ("Breaded veal cutlet", "Filete empanado", 255, 100, 150, 220, "meat"),
    ("San Jacobo", "San Jacobo", 270, 90, 130, 200, "meat"),
    ("Chicken nuggets", "Nuggets de pollo", 280, 70, 110, 170, "meat"),
    ("Fried egg", "Huevo frito", 200, 50, 60, 120, "egg"),
    ("Boiled egg", "Huevo cocido", 150, 50, 60, 120, "egg"),
    ("Scrambled eggs", "Huevos revueltos", 170, 80, 120, 180, "egg"),
    ("Hake", "Merluza", 110, 100, 150, 220, "fish"),
    ("Battered fish", "Pescado rebozado", 230, 100, 150, 220, "fish"),
    ("Cod", "Bacalao", 110, 100, 150, 220, "fish"),
    ("Sardines", "Sardinas", 200, 60, 100, 160, "fish"),
    ("Fried anchovies", "Boquerones fritos", 250, 80, 120, 180, "fish"),
    ("Fried squid rings", "Calamares a la romana", 250, 80, 130, 200, "fish"),
    ("Canned tuna", "Atún en lata", 190, 50, 80, 120, "fish"),
    ("Octopus", "Pulpo", 100, 80, 130, 200, "fish"),
    ("Sea bream", "Dorada", 150, 120, 180, 250, "fish"),
    ("Prawns", "Langostinos", 100, 60, 100, 160, "fish"),
    # Stews, spoon dishes and Spanish home cooking
    ("Lentil stew", "Lentejas guisadas", 120, 200, 300, 400, "stew"),
    ("Cocido madrileno", "Cocido madrileño", 150, 250, 350, 500, "stew"),
    ("Chickpea stew", "Potaje de garbanzos", 125, 200, 300, 400, "stew"),
    ("White bean stew", "Alubias guisadas", 130, 200, 300, 400, "stew"),
    ("Beef stew", "Estofado de ternera", 135, 200, 300, 400, "stew"),
    ("Chicken stew", "Pollo guisado", 130, 200, 300, 400, "stew"),
    ("Marmitako", "Marmitako", 105, 200, 300, 400, "stew"),
    ("Noodle soup", "Sopa de fideos", 45, 200, 300, 400, "soup"),
    ("Chicken broth", "Caldo de pollo", 15, 200, 250, 350, "soup"),
    ("Vegetable cream soup", "Crema de verduras", 55, 200, 300, 400, "soup"),
    ("Pumpkin cream soup", "Crema de calabaza", 50, 200, 300, 400, "soup"),
    ("Garlic soup", "Sopa de ajo", 70, 200, 300, 400, "soup"),
    ("Cuban rice", "Arroz a la cubana", 160, 200, 300, 400, "rice"),
    ("Rice with chicken", "Arroz con pollo", 150, 200, 300, 400, "rice"),
    ("Black rice", "Arroz negro", 150, 200, 300, 400, "rice"),
    ("Rice three delights", "Arroz tres delicias", 165, 150, 250, 350, "rice"),
    ("Fideua", "Fideuá", 160, 200, 300, 400, "pasta"),
    ("Pasta with tomato sauce", "Macarrones con tomate", 140, 200, 300, 400, "pasta"),
    ("Pasta bolognese", "Pasta boloñesa", 150, 200, 300, 400, "pasta"),
    ("Pasta salad", "Ensalada de pasta", 160, 150, 250, 350, "pasta"),
    ("Cannelloni", "Canelones", 150, 150, 250, 350, "pasta"),
    ("Pisto", "Pisto", 70, 150, 220, 300, "vegetable"),
    ("Migas", "Migas", 280, 150, 220, 300, "stew"),
    ("Huevos rotos", "Huevos rotos con jamón", 215, 200, 300, 400, "egg"),
    ("Callos", "Callos", 160, 150, 250, 350, "stew"),
    ("Stuffed peppers", "Pimientos rellenos", 150, 120, 200, 300, "vegetable"),
    ("Flamenquin", "Flamenquín", 280, 100, 160, 240, "meat"),
    ("Cachopo", "Cachopo", 270, 200, 350, 500, "meat"),
    ("Combo plate", "Plato combinado", 190, 300, 420, 550, "dish"),
    ("Mixed salad", "Ensalada mixta", 75, 150, 250, 350, "vegetable"),
    ("Tomato salad", "Ensalada de tomate", 60, 120, 200, 300, "vegetable"),
    ("Grilled vegetables", "Verduras a la plancha", 70, 120, 200, 300, "vegetable"),
    ("Sauteed green beans", "Judías verdes salteadas", 75, 120, 200, 300, "vegetable"),
    ("Sauteed mushrooms", "Champiñones salteados", 70, 80, 150, 220, "vegetable"),
    ("Roasted peppers", "Pimientos asados", 60, 60, 120, 200, "vegetable"),
    ("Mashed potatoes", "Puré de patatas", 105, 120, 200, 300, "side"),
    ("Roast potatoes", "Patatas asadas", 130, 120, 200, 300, "side"),
    ("Potato chips", "Patatas fritas de bolsa", 540, 20, 40, 80, "snack"),
    ("Olives", "Aceitunas", 145, 20, 40, 80, "snack"),
    ("Mixed nuts", "Frutos secos", 600, 20, 30, 60, "snack"),
    # Ready meals and fast food
    ("Frozen pizza", "Pizza precocinada", 250, 150, 300, 400, "ready meal"),
    ("Ready meal lasagna", "Lasaña precocinada", 145, 250, 350, 450, "ready meal"),
    ("Empanadilla", "Empanadillas", 290, 60, 120, 180, "ready meal"),
    ("Chicken fajita", "Fajita de pollo", 180, 150, 250, 350, "ready meal"),
    ("Burrito", "Burrito", 200, 200, 300, 400, "ready meal"),
    ("Poke bowl", "Poke bowl", 140, 300, 400, 500, "ready meal"),
    ("Instant noodles", "Fideos instantáneos", 110, 250, 350, 450, "ready meal"),
    ("Chicken and rice bowl", "Arroz con pollo y verduras", 140, 250, 350, 450, "ready meal"),
    ("Cheeseburger", "Hamburguesa con queso", 265, 120, 180, 260, "fast food"),
    ("Shawarma plate", "Plato de kebab", 190, 300, 400, 500, "fast food"),
    ("Quesadilla", "Quesadilla", 290, 100, 180, 260, "fast food"),
    # Sauces and fats
    ("Mayonnaise", "Mayonesa", 680, 10, 15, 30, "sauce"),
    ("Ketchup", "Kétchup", 110, 10, 15, 30, "sauce"),
    ("Alioli", "Alioli", 650, 10, 15, 30, "sauce"),
    ("Butter", "Mantequilla", 740, 5, 10, 20, "fat"),
    ("Jam", "Mermelada", 250, 10, 20, 40, "sauce"),
    # Fruit and desserts
    ("Grapes", "Uvas", 70, 80, 120, 200, "fruit"),
    ("Watermelon", "Sandía", 30, 150, 250, 400, "fruit"),
    ("Melon", "Melón", 35, 150, 250, 400, "fruit"),
    ("Pear", "Pera", 57, 120, 170, 220, "fruit"),
    ("Peach", "Melocotón", 40, 100, 150, 200, "fruit"),
    ("Mandarin", "Mandarina", 53, 60, 120, 200, "fruit"),
    ("Kiwi", "Kiwi", 60, 70, 100, 180, "fruit"),
    ("Pineapple", "Piña", 50, 100, 150, 250, "fruit"),
    ("Fruit salad", "Macedonia de frutas", 55, 120, 200, 300, "fruit"),
    ("Flan", "Flan", 145, 100, 125, 200, "dessert"),
    ("Rice pudding", "Arroz con leche", 130, 120, 170, 250, "dessert"),
    ("Custard", "Natillas", 120, 100, 125, 200, "dessert"),
    ("Torrija", "Torrijas", 250, 70, 120, 200, "dessert"),
    ("Chocolate", "Chocolate", 540, 15, 30, 60, "dessert"),
    ("Turron", "Turrón", 520, 20, 40, 70, "dessert"),
    # Drinks
    ("Coffee with milk", "Café con leche", 35, 120, 200, 300, "drink"),
    ("Orange juice", "Zumo de naranja", 45, 150, 250, 350, "drink"),
    ("Cola soft drink", "Refresco de cola", 42, 200, 330, 500, "drink"),
    ("Beer", "Cerveza", 43, 200, 330, 500, "drink"),
    ("Red wine", "Vino tinto", 85, 100, 150, 250, "drink"),
    ("Hot chocolate", "Chocolate a la taza", 95, 150, 200, 300, "drink"),
    ("Milkshake", "Batido", 90, 200, 300, 400, "drink"),
    ("Smoothie", "Smoothie de frutas", 55, 200, 300, 400, "drink"),
]


def main() -> None:
    root = Path(__file__).resolve().parents[1] / "lib/data/local"
    names = [row[0].lower() for row in ROWS] + [
        row[1].lower() for row in ROWS if row[1].lower() != row[0].lower()
    ]
    duplicates = {name for name in names if names.count(name) > 1}
    if duplicates:
        raise SystemExit(f"Duplicate names: {sorted(duplicates)}")

    # Earlier tables win on name collisions in NutritionRepository, so a
    # colliding row here would be silently unreachable.
    taken = set()
    for table in ("nutrition_database.json", "food101_nutrition.json"):
        for food in json.loads((root / table).read_text(encoding="utf-8")):
            taken.add(food["name"].lower())
            taken.add((food.get("nameEs") or "").lower())
    collisions = sorted(name for name in names if name in taken)
    if collisions:
        raise SystemExit(f"Already defined in another table: {collisions}")

    foods = [
        {
            "name": name,
            "nameEs": name_es,
            "kcalPer100g": kcal,
            "defaultGramsSmall": small,
            "defaultGramsMedium": medium,
            "defaultGramsLarge": large,
            "category": category,
            "source": "Generic composition estimate",
        }
        for name, name_es, kcal, small, medium, large, category in ROWS
    ]
    output = root / "common_foods_es.json"
    output.write_text(
        json.dumps(foods, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Wrote {len(foods)} foods to {output}")


if __name__ == "__main__":
    main()
