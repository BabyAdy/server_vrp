ICOANE PENTRU ITEME
===================

Pune aici fisiere PNG (recomandat 96x96 sau 128x128, fundal transparent).

Numele fisierului = cheia itemului din Config.Items, ex:
  water.png
  bread.png
  weapon_pistol.png
  ammo_pistol.png
  clothing_cap.png

Se incarca AUTOMAT - nu trebuie sa configurezi nimic in config.lua.
Daca vrei alt nume de fisier, pune-l explicit pe item:
  water = { label = 'Sticla de apa', ..., image = 'apa_minerala.png' }

Daca lipseste imaginea, se afiseaza un badge cu primele 3 litere.
Formate acceptate: .png .webp .jpg .svg
Dupa ce adaugi/modifici imagini: restart ph_inventory (sau refresh la resursa).
