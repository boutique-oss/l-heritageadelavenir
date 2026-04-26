"""
Test de génération d'image Gemini pour le modèle "Héritage"
Génère une image illustrant le fauteuil Héritage éco-sourcé avec son tarif en euros.
"""

from google import genai
from google.genai import types
from PIL import Image

client = genai.Client()

HERITAGE_COST = {
    "structure": 150,   # Bois CP (FAB LAB)
    "garnissage": 50,   # Mousse copeaux + sangles
    "couverture": 0,    # Cuir recyclé
    "fournitures": 200,
    "main_oeuvre": 1650,  # 30h × 55€/h
}
HERITAGE_TOTAL = sum(HERITAGE_COST.values())  # 2 050 €

prompt = (
    f"Create a photorealistic image of an elegant eco-friendly upholstered armchair "
    f"called 'Héritage', crafted from sustainable materials: recycled plywood structure, "
    f"jute straps, chip foam padding, and recycled leather cover in warm orange tones. "
    f"The armchair is displayed in a French artisan workshop with soft natural lighting. "
    f"In the lower-right corner, show a discreet price tag reading '{HERITAGE_TOTAL} €'. "
    f"The style is artisanal, warm, and sustainably crafted."
)

print(f"Modèle : Héritage — Coût total : {HERITAGE_TOTAL} €")
print("Envoi de la requête à Gemini…")

response = client.models.generate_content(
    model="gemini-2.5-flash-image",
    contents=[prompt],
    config=types.GenerateContentConfig(
        response_modalities=["TEXT", "IMAGE"],
    ),
)

for part in response.candidates[0].content.parts:
    if part.text is not None:
        print("Réponse texte :", part.text)
    elif part.inline_data is not None:
        image = Image.open(__import__("io").BytesIO(part.inline_data.data))
        output_path = "heritage_euro.png"
        image.save(output_path)
        print(f"Image générée et sauvegardée : {output_path}")
