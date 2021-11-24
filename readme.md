**Skrypt do pórywnywania wyników dla sklepów analogicznych 'like for like'**

---
Baza danych składa się z raportu sprzedaży dziennej wraz ze szczegółowymi informacjami dotyczącymi sprzedaży per sklep oraz informacji o dacie otwarcia danego sklepu.  
Wymienione raporty zostały zaczytane do bazy danych PostgreSQL, połączone kluczem głównym (Nazwa Sklepu) i następnie wykorzystując tabele tymczasowe oraz CTE (common table expression) zostały opracowane przykładowe widoki.

Zrzut z bazy danych:
![original_ds](screen/original_ds.png)

<br>

***Dane przedstawione w repozytorium są wstawione losowo na potrzeby prezentacji***


Wynikiem naszych zapytań są następujące, przykładowe widoki przedstawiające:
- miary sprzedażowe per tydzień dla sklepów analogicznych
![v_lfl20_per_week](screen/v_lfl20_per_week.PNG)

- podsumowanie miar sprzedażowych dla danego tygodnia r/r
![wyniki_tydz_rr](screen/wyniki_tydz_rr.PNG)

- podsumowanie miar sprzedażowych dla danego miesiąca r/r
![wyniki_miesiac_rr](screen/wyniki_miesiac_rr.PNG)



