/* ----------------------------------------------------------
   i18n dictionaries (da, sv, en) + fallback helper `_t`
   - Picks language from window.__BRAND.lang if present,
     otherwise falls back to <html lang> or 'da'.
---------------------------------------------------------- */
(function(){

  const DICTS = {
    /* ===================== DANISH (source of truth) ===================== */
    da: {
      /* overskrifter */
      HEADER_PENDING          : 'Dokumenter afventer din godkendelse',
      HEADER_ALL_OK           : '• Du har godkendt alle dokumenter',
      HEADER_ALL_OK_SHORT     : 'Godkendt',

      /* OTP */
      OTP_TITLE      : 'Bekræft din identitet',
      /* UPDATED: uses {btn} token and mentions email/SMS choice */
      OTP_SUBTITLE   : 'Vælg om du ønsker at bekræfte din identitet via e-mail eller SMS. <br>Husk at indtaste samme information, som du har brugt i dialogen med os tidligere. <br>Når du har trykket på “{btn}”, vil du modtage en kode på den valgte kanal.',
      /* UPDATED label */
      OTP_RESEND_BTN : 'Tilsend kode',
      OTP_VERIFY_BTN : 'Verificér & Vis',
      OTP_SENDING    : 'Sender kode…',
      OTP_SENT       : 'Kode sendt',
      /* OTP (identifier start) */
      OTP_USE_PHONE : 'Telefon',
      OTP_USE_EMAIL : 'E-mail',
      OTP_INPUT_PHONE: 'Indtast telefonnummer',
      OTP_INPUT_EMAIL: 'Indtast e-mail',

      /* (NEW) Verify step copy */
      START_OVER_BTN      : 'Start forfra',
      VERIFY_SUB_TPL      : 'Hvis vi fandt et match for {channel} {value}, har vi sendt en 6-cifret kode – indtast den her.',
      VERIFY_CHANNEL_EMAIL: 'din e-mail',
      VERIFY_CHANNEL_PHONE: 'telefon',

      /* ===== Common runtime messages & errors ===== */
      LOADING            : 'Indlæser…',
      GENERIC_SENDING    : 'Sender…',
      GENERIC_ERROR      : 'Noget gik galt…',
      GENERIC_DOC        : 'Dokument',
      LIST_FAILED        : 'Kunne ikke hente liste',
      NO_DOCS_NEWEST     : 'Ingen dokumenter med nyeste version blev fundet',
      NO_DOCUMENTS_FOUND : 'Ingen dokumenter fundet',
      PRESIGN_FAILED     : 'Kunne ikke hente dokumentet',
      APPROVED_DOC       : '{name} er godkendt',
      APPROVE_THANKS     : 'Tak for din godkendelse ✔',

      /* OTP fallbacks */
      OTP_INVALID        : 'Ugyldig kode',
      OTP_RESEND_FAILED  : 'Kunne ikke gensende',

      /* Impersonation */
      IMPERSONATION_MODE       : 'Logget ind som klient',
      READ_ONLY                : 'Skrivebeskyttet',
      IMPERSONATION_ERROR_TITLE: 'Link fejl',
      IMPERSONATION_ERROR_HINT : 'Adgangslinks kan kun benyttes én gang. Dette link har allerede været i brug.',

      /* sidebar */
      SIDEBAR_PENDING  : 'Afventer',
      SIDEBAR_APPROVED : 'Godkendt',
      APPROVE_ALL_BTN  : 'Godkend alle',

      /* empty states */
      PENDING_EMPTY  : 'Der er ikke flere dokumenter, der afventer din godkendelse.',
      APPROVED_EMPTY : 'Ingen dokumenter er godkendt endnu.',

      /* viewer buttons */
      INTRO_BTN     : 'Se 60-sekunders intro-video',
      DOWNLOAD_BTN  : 'Download PDF',
      PRINT_BTN     : 'Udskriv PDF',
      PDF_VIEWER_TIP: 'Har du svært ved at se PDF\'en? Tryk på "Download PDF" for at åbne den i en separat PDF-læser.',

      /* modal-knapper & tekster */
      MODAL_CANCEL      : 'Annullér',
      MODAL_APPROVE     : 'Godkend',
      MODAL_APPROVE_ALL : 'Godkend alle dokumenter',
      MODAL_APPROVE_TXT : 'Når du trykker <strong>Godkend</strong>, bekræfter du at du er helt tilfreds med indholdet af',
      MODAL_APPROVE_ALL_TXT: 'Når du trykker <strong>Godkend alle dokumenter</strong>, bekræfter du at du er helt tilfreds med indholdet af følgende dokumenter:',

      /* succes-tekster */
      SUCCESS_PREFIX : '• ',
      APPROVE_PREFIX : 'Godkend',
      
      /* blocked approval */
      BLOCKED_APPROVAL_HEADER : 'Dokumentet kan ikke godkendes',
      BLOCKED_APPROVAL_BODY : 'Din jurist har deaktiveret muligheden for at godkende dette dokument, da der mangler oplysninger, før du kan afgive din endelige godkendelse. Hvis du stadig er i tvivl om, hvad der mangler, efter at have læst dokumentet igennem, så brug chatten til højre for at kontakte os.',
      APPROVAL_BLOCKED_HINT : 'Kan ikke godkendes endnu. Information mangler.',
      APPROVAL_BLOCKED_TOOLTIP : 'Kan ikke godkendes endnu. Information mangler.',
      CLOSE : 'Luk',

      /* chat */
      CHAT_HEADER       : 'Chat',
      CHAT_HEADER_OPEN  : 'Skriv til os',
      CHAT_PLACEHOLDER  : 'Skriv her…',
      CHAT_NO_MESSAGES  : 'Ingen beskeder endnu.',
      CHAT_LABEL        : 'Skriv til os her',
      CHAT_DISCLAIMER   : 'Denne chat er ikke live. Vi sigter mod at svare inden for 2 arbejdsdage.',
      CHAT_EMPTY        : 'Ingen beskeder endnu. Send en besked for at starte samtalen.',
        CHAT_NO_DOC_WARNING: {
    da: "Åbn venligst et dokument først for at se relaterede beskeder.",
    sv: "Öppna ett dokument först för att se relaterade meddelanden.",
    en: "Please open a document first to see related messages."
  },
  
  // Journal selection (bridge page)
  JOURNAL_OVERVIEW_TITLE: {
    da: "Oversigt",
    sv: "Översikt",
    en: "Overview"
  },
  JOURNAL_SELECT_TITLE: {
    da: "Vælg journal",
    sv: "Välj journal",
    en: "Select Journal"
  },
  JOURNAL_SELECT_DESC: {
    da: "Vi har fundet dokumenter relateret til flere journaler. Vælg venligst den journal, du vil se dokumenter for:",
    sv: "Vi har hittat dokument relaterade till flera journaler. Välj den journal du vill se dokument för:",
    en: "We found documents related to multiple journals. Please select the journal you want to view documents for:"
  },
  JOURNAL_DOCUMENTS_COUNT: {
    da: "{count} dokument(er)",
    sv: "{count} dokument",
    en: "{count} document(s)"
  },
  JOURNAL_ALL_APPROVED: {
    da: "✓ Alle godkendt",
    sv: "✓ Alla godkända",
    en: "✓ All approved"
  },
  BACK_TO_OVERVIEW: {
    da: "← Tilbage til oversigt",
    sv: "← Tillbaka till översikt",
    en: "← Back to Overview"
  },
  BACK_TO_JOURNALS: {
    da: "← Tilbage til journaler",
    sv: "← Tillbaka till journaler",
    en: "← Back to Journals"
  },
  JOURNAL_FIRST_DRAFT_SENT: {
    da: "Første udkast tilsendt: ",
    sv: "Första utkastet skickat: ",
    en: "First draft sent: "
  },

      /* intro-modal */
      INTRO_TITLE : 'Velkommen til din dokument­portal',
      INTRO_H3A   : 'Hvad sker der nu?',
      INTRO_P1    : `
        <ul>
          <li>Nu skal du/I læse dokumenterne godt igennem.</li>
          <li>Er der noget markeret med rødt, er det nogle informationer vi mangler.</li>
          <li>Er der nogen rettelser eller spørgsmål, så kan du/I skrive til juristen i chatten nede til højre.</li>
          <li>I kan også skrive at I ønsker et opkald, og så ringer juristen og aftaler en tid og dato.</li>
        </ul>
      `,
      INTRO_H3B   : 'Sådan godkender du/I dokumenterne',
      INTRO_P2    : `
        <ul>
          <li>Ude til venstre kan der klikkes på hvert enkelt dokument.</li>
          <li>Hvis der ikke er flere rettelser eller spørgsmål, samt der ikke er noget der er markeret med rødt, så klikkes der på knappen <strong>Godkend</strong> – så er det givne dokument godkendt.</li>
          <li>Når alle dokumenterne er godkendt, vil der blive sendt mails ud med afsluttende processer, så du/I ikke er i tvivl om hvad der skal gøres.</li>
        </ul>
      `,
      INTRO_CLOSE_BTN : 'Luk og se dokumenter',

      /* FAQ */
      FAQ_BTN       : 'Ofte stillede spørgsmål',
      FAQ_TITLE     : 'Ofte stillede spørgsmål',
      FAQ_CLOSE_BTN : 'Luk',
      FAQ_SECTION1  : 'Testamente',
      FAQ_SECTION2  : 'Fremtidsfuldmagt',
      FAQ_SECTION3  : 'Ægtepagt',
      FAQ_SECTION4  : 'Generalfuldmagt',

      /* FAQ bodies (HTML) */
      FAQ_SECTION1_BODY : `
        <div class="faq-block">
          <h4>Gravstedsvedligeholdelse</h4>
          <p>Denne paragraf giver jeres arvinger mulighed for <strong>skattefrit</strong> at trække udgiften til et gravsted ud af boet. Det er en mulighed – ikke et krav.</p>
        </div>

        <div class="faq-block">
          <h4>Hvad er tvangsarv og friarv?</h4>
          <p><strong>Tvangsarv</strong> er 25% af den arv, du efterlader dig. Den skal gå til ægtefælle og livsarvinger.</p>
          <ul>
            <li>Ægtefælle: 12,5%</li>
            <li>Livsarvinger: 12,5% til deling mellem børn/børnebørn</li>
          </ul>
          <p><strong>Friarv</strong> er 75%, som du frit kan disponere over i testamentet.</p>
          <p>Hvis der hverken er ægtefælle eller livsarvinger, har du 100% friarv.</p>
        </div>

        <div class="faq-block">
          <h4>Jeg har hørt om 6,25% tvangsarv – hvad betyder det?</h4>
          <p>Tvangsarven er samlet 25%. At se <strong>6,25%</strong> kan give mening i en konkret familiesituation – fx <em>ægtefælle (12,5%) og to børn</em>, der deler 12,5% = <strong>6,25% til hvert barn</strong>. Tallene ændrer sig ved flere/færre børn eller ingen ægtefælle.</p>
        </div>

        <div class="faq-block">
          <h4>Hvad er en forvaltningsafdeling?</h4>
          <p>Hvis arv båndlægges, vælger skifteretten en <em>godkendt forvaltningsafdeling</em> (bankafdeling godkendt til at forvalte båndlagt arv). Fx Nordea, Danske Bank og Spar Nord har sådanne afdelinger.</p>
        </div>

        <div class="faq-block">
          <h4>Successionsrækkefølge (forklaring)</h4>
          <p>“Successionsrækkefølge” er rækkefølgen for arvefølge, hvis der stadig er arv, når en arving går bort. Eksempel: barn arver → barnet går bort → barnebarn arver det resterende → oldebarn osv.</p>
        </div>

        <div class="faq-block">
          <h4>Pensioner og forsikringer</h4>
          <p>Fordeles som udgangspunkt <strong>ikke</strong> via testamentet, men efter begunstigelser hos pensions-/forsikringsselskaber. Kontakt selskaberne for aktuel fordeling og ændringer. I visse situationer kan udbetalinger indgå i boet og følge testamentet.</p>
        </div>
      `,

      FAQ_SECTION2_BODY : `
        <div class="faq-block">
          <h4>Hvorfor står XXXX i stedet for de sidste 4 cifre i CPR-nummeret?</h4>
          <p>Fremtidsfuldmagter registreres i <strong>Tingbogen</strong>, et offentligt system. Personer registreres med fuldt CPR, men de sidste fire cifre skjules på dokumentet af hensyn til privatliv.</p>
        </div>

        <div class="faq-block">
          <h4>§ 7.2 – Udarbejdelse af årligt regnskab</h4>
          <p>Det er et lovkrav, der <strong>ikke kan fraviges</strong>. Der behøver ikke være revisor/bogholder; en <em>bankudskrift med bilag</em> for hver transaktion er tilstrækkeligt, så Familieretshuset kan føre tilsyn.</p>
        </div>

        <div class="faq-block">
          <h4>§ 12.1 – Kan jeg komme under værgemål, selvom jeg har fremtidsfuldmagt?</h4>
          <p>Kun hvis <strong>alle</strong> fuldmægtige ikke kan eller vil varetage fuldmagten. Så udpeger Familieretshuset en <em>professionel værge</em>, så dine interesser stadig varetages.</p>
        </div>
      `,

      FAQ_SECTION3_BODY : `
        <p>Indhold kommer snart. Har du spørgsmål om ægtepagt nu, så skriv til os i chatten – vi hjælper gerne.</p>
      `,

      FAQ_SECTION4_BODY : `
        <div class="faq-block">
          <h4>Hvad er forskellen på generalfuldmagt og fremtidsfuldmagt?</h4>
          <p><strong>Generalfuldmagt</strong> bruges mens du stadig er ved dine fulde fem, men pga. alderdom/sygdom har brug for hjælp i hverdagen. Den er praktisk – især i tiden <em>inden</em> en fremtidsfuldmagt sættes i kraft.</p>
          <p><strong>Fremtidsfuldmagt</strong> bruges, når du <em>ikke</em> længere er ved dine fulde fem. Den kræver lægeerklæring og sættes i kraft via Familieretshuset. Processen kan tage måneder – her “griber” generalfuldmagten dig i mellemtiden.</p>
        </div>

        <div class="faq-block">
          <h4>Hvorfor står der kun én person på min generalfuldmagt?</h4>
          <p>Der angives typisk <strong>én</strong> fuldmægtig for at undgå tvivl om, hvem der kan handle. Det giver en enklere og mere klar proces over for banker, myndigheder m.fl.</p>
          <p>Det er muligt at <strong>overdrage</strong> generalfuldmagten til en anden person, hvis dokumentet giver adgang til det. Det vil fremgå (ofte i afsnit 2–3). Kun du som fuldmagtsgiver kan beslutte en overdragelse.</p>
        </div>
      `,

      /* post-approval modal */
      POST_APPROVAL_TITLE : 'Alle dokumenter er godkendt',
      POST_APPROVAL_H3A   : 'Tak for din godkendelse',
      POST_APPROVAL_P1    : `
        <p>Alle dokumenter er nu godkendt.</p>
        <p>Tak for din/jeres godkendelse.</p>
        <p>Dette betyder at du/I ikke har flere spørgsmål eller rettelser, og der ikke er mere der er markeret med rødt (informationer der manglede).</p>
      `,
      POST_APPROVAL_H3B   : 'Hvad sker der nu?',
      POST_APPROVAL_P2    : `
        <p>Vi vil nu sende afsluttende proces-mail for hver af de forskellige dokumenter, som beskriver hvad der skal gøres for at gyldiggøre dokumentet.</p>
        <p>De bliver kun sendt til den mail vi har brugt under hele forløbet. Hvis I er flere, skal alle følge de vejledninger der er.</p>
      `,
      POST_APPROVAL_CLOSE_BTN : 'Luk',
      POST_APPROVAL_VIEW_BTN  : 'Vis kvittering',

      /* tour (in-app guidance) */
      TOUR_CLOSE        : 'Luk guide',
      TOUR_BACK         : 'Tilbage',
      TOUR_NEXT         : 'Næste',
      TOUR_DONE         : 'Forstået',
      TOUR_STEP_SIDEBAR : 'Her kan du se en liste over dine dokumenter.',
      TOUR_STEP_FAQ     : 'Her kan du finde svar på de mest gængse spørgsmål',
      TOUR_STEP_PDF     : 'Her kan du se indholdet af dokumentet. Læs det igennem og sikr dig, at alt er som du ønsker.',
      TOUR_STEP_CHAT    : 'Hvis du har spørgsmål, kan du skrive til os her. Vi svarer inden for 3-5 hverdage – ofte hurtigere!',
      TOUR_STEP_APPROVE : 'Når du er tilfreds, klikker du “Godkend”.',
      TOUR_STEP_DOWNLOAD: 'Med disse knapper kan du downloade eller udskrive dokumentet som PDF.',
      TOUR_RELAUNCH     : 'Start guide igen',

      /* footer */
      FOOTER_TEXT : '&copy; 2019 Din Familiejurist • Brug for hjælp? <a href="mailto:kontakt@dinfamiliejurist.dk">kontakt@dinfamiliejurist.dk</a>',

      /* fallback */
      MISSING : '[MISSING TEXT]'
    },

    /* ===================== SWEDISH ===================== */
    sv: {
      /* rubriker */
      HEADER_PENDING          : 'Dokument väntar på ditt godkännande',
      HEADER_ALL_OK           : '• Du har godkänt alla dokument',
      HEADER_ALL_OK_SHORT     : 'Godkänd',

      /* OTP */
      OTP_TITLE      : 'Bekräfta din identitet',
      /* UPDATED */
      OTP_SUBTITLE   : 'Välj om du vill bekräfta din identitet via e-post eller SMS. <br>Kom ihåg att ange samma uppgifter som du tidigare har använt i kontakten med oss. <br>När du har tryckt på “{btn}” får du en kod på den valda kanalen.',
      /* UPDATED label */
      OTP_RESEND_BTN : 'Skicka kod',
      OTP_VERIFY_BTN : 'Verifiera & Visa',
      OTP_SENDING    : 'Skickar kod',
      OTP_SENT       : 'Kod skickad',
      OTP_USE_PHONE : 'Telefon',
      OTP_USE_EMAIL : 'E-post',
      OTP_INPUT_PHONE: 'Ange telefonnummer',
      OTP_INPUT_EMAIL: 'Ange e-post',

      /* (NEW) Verify step copy */
      START_OVER_BTN      : 'Börja om',
      VERIFY_SUB_TPL      : 'Om vi hittade en matchning för {channel} {value}, har vi skickat en 6-siffrig kod – ange den här.',
      VERIFY_CHANNEL_EMAIL: 'din e-post',
      VERIFY_CHANNEL_PHONE: 'telefon',

      /* SV */
      LOADING            : 'Läser in…',
      GENERIC_SENDING    : 'Skickar…',
      GENERIC_ERROR      : 'Något gick fel…',
      GENERIC_DOC        : 'Dokument',
      LIST_FAILED        : 'Kunde inte hämta listan',
      NO_DOCS_NEWEST     : 'Inga dokument med senaste version hittades',
      NO_DOCUMENTS_FOUND : 'Inga dokument hittades',
      PRESIGN_FAILED     : 'Kunde inte hämta dokumentet',
      APPROVED_DOC       : '{name} är godkänt',
      APPROVE_THANKS     : 'Tack för ditt godkännande ✔',

      OTP_INVALID        : 'Ogiltig kod',
      OTP_RESEND_FAILED  : 'Kunde inte skicka igen',

      /* Impersonation */
      IMPERSONATION_MODE       : 'Inloggad som klient',
      READ_ONLY                : 'Skrivskyddad',
      IMPERSONATION_ERROR_TITLE: 'Länkfel',
      IMPERSONATION_ERROR_HINT : 'Åtkomstlänkar kan endast användas en gång. Den här länken har redan använts.',

      /* sidofält */
      SIDEBAR_PENDING  : 'Väntar',
      SIDEBAR_APPROVED : 'Godkänd',
      APPROVE_ALL_BTN  : 'Godkänn alla',

      /* tomma tillstånd */
      PENDING_EMPTY  : 'Det finns inga fler dokument som väntar på ditt godkännande.',
      APPROVED_EMPTY : 'Inga dokument har godkänts ännu.',

      /* visningsknappar */
      INTRO_BTN     : 'Se 60-sekunders introduktionsvideo',
      DOWNLOAD_BTN  : 'Ladda ner PDF',
      PRINT_BTN     : 'Skriv ut PDF',
      PDF_VIEWER_TIP: 'Har du svårt att se PDF:en? Klicka på "Ladda ner PDF" för att öppna den i en separat PDF-läsare.',

      /* modal-knappar & texter */
      MODAL_CANCEL      : 'Avbryt',
      MODAL_APPROVE     : 'Godkänn',
      MODAL_APPROVE_ALL : 'Godkänn alla dokument',
      MODAL_APPROVE_TXT : 'När du klickar på <strong>Godkänn</strong> bekräftar du att du är helt nöjd med innehållet i',
      MODAL_APPROVE_ALL_TXT: 'När du klickar på <strong>Godkänn alla dokument</strong>, bekräftar du att du är helt nöjd med innehållet i följande dokument:',

      /* framgångstexter */
      SUCCESS_PREFIX : '• ',
      APPROVE_PREFIX : 'Godkänn',
      
      /* blockerat godkännande */
      BLOCKED_APPROVAL_HEADER : 'Dokumentet kan inte godkännas',
      BLOCKED_APPROVAL_BODY : 'Din jurist har inaktiverat möjligheten att godkänna detta dokument, eftersom viss information fortfarande krävs innan du kan lämna ditt slutgiltiga godkännande. Om du fortfarande är osäker på vad som saknas efter att ha läst igenom ditt dokument, vänligen använd chatten till höger för att kontakta oss.',
      APPROVAL_BLOCKED_HINT : 'Kan inte godkännas ännu. Information saknas.',
      APPROVAL_BLOCKED_TOOLTIP : 'Kan inte godkännas ännu. Information saknas.',
      CLOSE : 'Stäng',

      /* chatt */
      CHAT_HEADER       : 'Chatt',
      CHAT_HEADER_OPEN  : 'Skriv till oss',
      CHAT_PLACEHOLDER  : 'Skriv här…',
      CHAT_NO_MESSAGES  : 'Inga meddelanden ännu.',
      CHAT_LABEL        : 'Skriv till oss här',
      CHAT_DISCLAIMER   : 'Denna chatt är inte live. Vi strävar efter att svara inom 5 arbetsdagar.',
      CHAT_EMPTY        : 'Inga meddelanden ännu. Skicka ett meddelande för att starta konversationen.',
      CHAT_NO_DOC_WARNING: 'Öppna ett dokument först för att se relaterade meddelanden.',

      /* intro-modal */
      INTRO_TITLE : 'Välkommen till din dokumentportal',
      INTRO_H3A   : 'Vad händer nu?',
      INTRO_P1    : `
        <ul>
          <li>Nu ska du/ni läsa igenom dokumenten noggrant.</li>
          <li>Om något är markerat med rött, betyder det att vi saknar information.</li>
          <li>Om det finns några rättelser eller frågor kan du/ni skriva till juristen i chatten nere till höger.</li>
          <li>Ni kan också skriva att ni önskar ett samtal, så ringer juristen upp och bokar en tid och datum.</li>
        </ul>
      `,
      INTRO_H3B   : 'Så här godkänner du/ni dokumenten',
      INTRO_P2    : `
      <ul>
          <li>
              Till vänster kan du klicka på varje enskilt dokument.
          </li>
          <li>
              Om det inte finns fler rättelser eller frågor, samt inget är markerat med rött, klickar du på knappen <strong>Godkänn</strong> – då är det aktuella dokumentet godkänt.
          </li>
          <li>
              När alla dokument är godkända skickas mejl ut med avslutande processer, så att du/ni inte är osäkra på vad som ska göras.
          </li>
      </ul>
      `,
      INTRO_CLOSE_BTN : 'Stäng och visa dokument',

      /* FAQ */
      FAQ_BTN       : 'Vanliga frågor',
      FAQ_TITLE     : 'Vanliga frågor',
      FAQ_CLOSE_BTN : 'Stäng',
      FAQ_SECTION1  : 'Testamente',
      FAQ_SECTION2  : 'Framtidsfullmakt',
      FAQ_SECTION3  : 'Äktenskapsförord',
      FAQ_SECTION4  : 'Generalfullmakt',

      FAQ_SECTION1_BODY : `
        <div class="faq-block">
          <h4>Gravskötsel</h4>
          <p>Denna paragraf ger era arvingar möjlighet att <strong>skattefritt</strong> ta kostnaden för gravskötsel ur dödsboet. Det är en möjlighet – inte ett krav.</p>
        </div>

        <div class="faq-block">
          <h4>Vad är tvingad arvslott och friarv?</h4>
          <p><strong>Tvingad arvslott</strong> är 25% av den kvarlåtenskap du lämnar efter dig. Den ska gå till make/maka och bröstarvingar.</p>
          <ul>
            <li>Make/maka: 12,5%</li>
            <li>Bröstarvingar: 12,5% att dela mellan barn/barnbarn</li>
          </ul>
          <p><strong>Friarv</strong> är 75% som du fritt kan förfoga över i testamentet.</p>
          <p>Om det saknas både make/maka och bröstarvingar har du 100% friarv.</p>
        </div>

        <div class="faq-block">
          <h4>Jag hörde 6,25% tvingad arvslott – vad betyder det?</h4>
          <p>Den totala tvingade arvslotten är 25%. <strong>6,25%</strong> kan uppstå i ett exempel med <em>make/maka (12,5%) och två barn</em> som delar 12,5% = <strong>6,25% per barn</strong>. Procenten ändras vid fler/färre barn eller utan make/maka.</p>
        </div>

        <div class="faq-block">
          <h4>Vad är en förvaltningsavdelning?</h4>
          <p>När arv båndläggs utser tingsrätten en <em>godkänd förvaltningsavdelning</em> (bankavdelning som får hantera båndlagt arv). Exempelvis har Nordea, Danske Bank och Spar Nord sådana avdelningar.</p>
        </div>

        <div class="faq-block">
          <h4>Successionsordning (förklaring)</h4>
          <p>“Successionsordning” är turordningen för arv om det finns kvarlåtenskap när en arvinge går bort. Exempel: barn ärver → barnet går bort → barnbarn ärver resterande → barnbarnsbarn osv.</p>
        </div>

        <div class="faq-block">
          <h4>Pensioner och försäkringar</h4>
          <p>Fördelas i regel <strong>inte</strong> via testamentet, utan enligt förmånstagarförordnanden hos bolagen. Kontakta bolagen för aktuell fördelning och ändringar. I vissa fall kan utbetalningar ingå i boet och då följa testamentet.</p>
        </div>
      `,

      FAQ_SECTION2_BODY : `
        <div class="faq-block">
          <h4>Varför står XXXX i stället för de sista 4 siffrorna i personnumret?</h4>
          <p>Framtidsfullmakter registreras i <strong>inskrivningsregistret</strong> (Tingbogen), ett offentligt system. Personer registreras med fullständigt personnummer, men de sista fyra siffrorna döljs på dokumentet av integritetsskäl.</p>
        </div>

        <div class="faq-block">
          <h4>§ 7.2 – Årsredovisning</h4>
          <p>Detta är ett <strong>lagkrav</strong> och kan inte undvikas. Det krävs ingen revisor; en <em>kontoutdrag med bilagor</em> för varje transaktion räcker för att familjerätten ska kunna utöva tillsyn.</p>
        </div>

        <div class="faq-block">
          <h4>§ 12.1 – Kan jag få god man/förvaltare trots framtidsfullmakt?</h4>
          <p>Endast om <strong>samtliga</strong> fullmaktshavare inte kan eller vill sköta uppdraget. Då utser familjerätten en <em>professionell ställföreträdare</em> så att dina intressen tillvaratas.</p>
        </div>
      `,

      FAQ_SECTION3_BODY : `
        <p>Innehåll kommer snart. Har du frågor om äktenskapsförord redan nu, skriv i chatten så hjälper vi dig.</p>
      `,

      FAQ_SECTION4_BODY : `
        <div class="faq-block">
          <h4>Skillnaden mellan generalfullmakt och framtidsfullmakt</h4>
          <p><strong>Generalfullmakt</strong> används medan du fortfarande är beslutsförmögen men behöver hjälp i vardagen p.g.a. ålder/sjukdom. Den är praktisk – särskilt tiden <em>innan</em> en framtidsfullmakt eventuellt träder i kraft.</p>
          <p><strong>Framtidsfullmakt</strong> används när du <em>inte</em> längre är beslutsförmögen. Den kräver läkarintyg och sätts i kraft via familjerätten. Processen kan ta månader – här “fångar” generalfullmakten upp dig under tiden.</p>
        </div>

        <div class="faq-block">
          <h4>Varför står det bara en person på min generalfullmakt?</h4>
          <p>Det anges normalt <strong>en</strong> fullmaktshavare för att undvika oklarhet kring vem som får agera. Det gör processen enklare och tydligare gentemot banker och myndigheter.</p>
          <p>Det är möjligt att <strong>överlåta</strong> generalfullmakten till någon annan om dokumentet medger det. Det framgår i texten (ofta i avsnitt 2–3). Endast du som fullmaktsgivare kan besluta om överlåtelse.</p>
        </div>
      `,

      /* modal efter godkännande */
      POST_APPROVAL_TITLE : 'Alla dokument är godkända',
      POST_APPROVAL_H3A   : 'Tack för ditt godkännande',
      POST_APPROVAL_P1    : `
        <p>Alla dokument är nu godkända. Nedan hittar du en kort och praktisk översikt över nästa steg för respektive dokumenttyp.</p>

        <div class="faq-block">
          <h4>Testamente</h4>
          <p>Testamentet är nu färdigt för att skrivas under.</p>
          <p>För att göra ett testamente juridiskt bindande ska det skrivas under samt bevittnas. Du/Ni ska skriva under era dokument och samtidigt (fysiskt) ha två vittnen närvarande. Vittnena ska också skriva under testamentet och intyga vem/vilka som skriver under dokumentet, att personen/personerna är vid sina sinnes fulla bruk samt att personen/personerna gör detta av egen fri vilja. <em>Observera att vittnena inte får vara släktingar och inte heller vara nämnda i dokumenten.</em></p>
          <p>Testamentet ska inte registreras under tiden testatorn är vid liv och det är du själv som ansvarar för förvaringen. I samband med att du/ni går bort upprättas en bouppteckning och testamentet ska bifogas bouppteckningen. Vi rekommenderar därför att man underrättar närmast anhöriga om att ett testamente finns.</p>
        </div>

        <div class="faq-block">
          <h4>Framtidsfullmakt</h4>
          <p>För att göra en framtidsfullmakt juridiskt bindande ska fullmakten skrivas under samt bevittnas. Du/Ni ska skriva under era dokument och samtidigt (fysiskt) ha två vittnen närvarande. Vittnena ska också skriva under dokumentet och intyga vem/vilka som skriver under fullmakten, att personen/personerna är vid sina sinnes fulla bruk samt att personen/personerna gör detta av egen fri vilja. <em>Observera att vittnena inte får vara släktingar och inte heller vara nämnda i dokumenten.</em></p>
          <p>Framtidsfullmakten ska inte registreras och det är du själv som ansvarar för förvaringen. Framtidsfullmakten börjar användas den dag du själv är oförmögen att hantera de angelägenheter den omfattar. Vi rekommenderar dock att samtliga fullmaktshavare har en varsin upplaga av fullmakten.</p>
        </div>

        <div class="faq-block">
          <h4>Äktenskapsförord</h4>
          <p>Äktenskapsförordet ska signeras och vi rekommenderar starkt att man även har med två vittnen.</p>
          <p>När äktenskapsförordet är signerat ska det skickas in till Skatteverket för registrering. Följ instruktionerna i denna länk för att registrera äktenskapsförordet: <a href="https://www.skatteverket.se/privat/folkbokforing/aktenskapochpartnerskap/aktenskapsregistret/aktenskapsforord.4.8639d413207905e9480002503.html" target="_blank" rel="noopener">Skatteverket – Äktenskapsförord</a>.</p>
        </div>

        <div class="faq-block">
          <h4>Samboavtal</h4>
          <p>Vad gäller samboavtalet är det viktigt att ni får det signerat och gärna bevittnat. Det är inget krav att ha vittnen närvarande vid signeringen men vi rekommenderar att man har det.</p>
          <p>Samboavtalet är ett avtal mellan sambor som avtalar bort sambolagens regler om bodelning och ska <strong>inte</strong> registreras någonstans.</p>
        </div>

        <div class="faq-block">
          <h4>Gåvobrev – fastighet</h4>
          <p>Gåvobrevet ska signeras och bevittnas. När gåvobrevet är signerat ska det skickas in till Lantmäteriet för att ändra lagfart.</p>
          <p>Följ instruktionerna i denna länk för att registrera gåvobrevet: <a href="https://www.lantmateriet.se/sv/fastigheter/andra-agare/ansok-om-lagfart-eller-inskrivning-av-tomtrattsinnehav/ansokan-vid-gava/" target="_blank" rel="noopener">Lantmäteriet – Ansökan vid gåva</a>.</p>
          <p>Om det är en gåva mellan makar, oavsett om det gäller en fastighet eller annan egendom, kan man registrera den hos Skatteverket för att den ska gälla mot borgenärer.</p>
        </div>

        <div class="faq-block">
          <h4>Gåvobrev – annan egendom</h4>
          <p>Gåvobrevet ska signeras och gärna bevittnas. Det är inget krav att ha vittnen närvarande vid signeringen men vi rekommenderar att man har det.</p>
          <p>Gåvobrevet ska inte registreras någonstans, men om gåvan avser en bostadsrätt kan bostadsrättsföreningen begära att få ta del av gåvobrevet.</p>
          <p>Om det är en gåva mellan makar, oavsett om det gäller en fastighet eller annan egendom, kan man registrera den hos Skatteverket för att den ska gälla mot borgenärer.</p>
        </div>
      `,
      POST_APPROVAL_H3B   : 'Vad händer nu?',
      POST_APPROVAL_P2    : `
        <p>Vi skickar nu ut avslutande instruktioner per dokumenttyp till samma e-postadress som använts under ärendet. Följ anvisningarna steg för steg. Har du frågor – använd chatten så hjälper vi dig.</p>
      `,
      POST_APPROVAL_CLOSE_BTN : 'Stäng',
      POST_APPROVAL_VIEW_BTN  : 'Visa kvitto',

      /* guide (in-app) */
      TOUR_CLOSE        : 'Stäng guide',
      TOUR_BACK         : 'Tillbaka',
      TOUR_NEXT         : 'Nästa',
      TOUR_DONE         : 'Förstått',
      TOUR_STEP_SIDEBAR : 'Här kan du se en lista över dina dokument – prova att klicka på ett!',
      TOUR_STEP_FAQ     : 'Här kan du hitta svar på de vanligaste frågorna',
      TOUR_STEP_PDF     : 'Här kan du se dokumentets innehåll. Läs igenom det och säkerställ att allt är som du vill.',
      TOUR_STEP_CHAT    : 'Om du har frågor kan du skriva till oss här. Vi svarar dig inom de fem kommande arbetsdagarna.',
      TOUR_STEP_APPROVE : 'När du är nöjd klickar du “Godkänn” - du kommer då få ytterligare information om vad du ska tänka på vid den riktiga signeringen. ',
      TOUR_STEP_DOWNLOAD: 'Med dessa knappar kan du ladda ner eller skriva ut dokumentet som PDF.',
      TOUR_RELAUNCH     : 'Starta guiden igen',

      /* sidfot */
      FOOTER_TEXT : '&copy; 2025 Din Familjejurist • Behöver du hjälp? <a href="mailto:kontakt@dinfamiljejurist.se">kontakt@dinfamiljejurist.se</a>',

      /* reservtext */
      MISSING : '[SAKNAD TEXT]',

      /* ---- End bit (non-bulleted) – Swedish only ---- */
      END_NOTE_STYLE_PROMPT : 'Vill du att jag också gör en kortare, mer kundvänlig version (lite enklare språk) som kan användas direkt på portalen, eller vill du behålla den mer formella tonen?'
    },

    /* ===================== ENGLISH ===================== */
    en: {
      /* headings */
      HEADER_PENDING          : 'Documents awaiting your approval',
      HEADER_ALL_OK           : '• You have approved all documents',
      HEADER_ALL_OK_SHORT     : 'Approved',

      /* OTP */
      OTP_TITLE      : 'Confirm your identity',
      /* UPDATED */
      OTP_SUBTITLE   : 'Choose whether to verify your identity via email or SMS. <br>Please enter the same details you used previously in your communication with us. <br>After you click “{btn}”, you’ll receive a code on the selected channel.',
      /* UPDATED label */
      OTP_RESEND_BTN : 'Send code',
      OTP_VERIFY_BTN : 'Verify & View',
      OTP_SENDING    : 'Sending code',
      OTP_SENT       : 'Code sent',
      OTP_USE_PHONE : 'Phone',
      OTP_USE_EMAIL : 'Email',
      OTP_INPUT_PHONE: 'Enter phone number',
      OTP_INPUT_EMAIL: 'Enter email',

      /* (NEW) Verify step copy */
      START_OVER_BTN      : 'Start over',
      VERIFY_SUB_TPL      : 'If we found a match for {channel} {value}, we’ve sent you a 6-digit code — enter it here.',
      VERIFY_CHANNEL_EMAIL: 'your email',
      VERIFY_CHANNEL_PHONE: 'phone',

      /* EN */
      LOADING            : 'Loading…',
      GENERIC_SENDING    : 'Sending…',
      GENERIC_ERROR      : 'Something went wrong…',
      GENERIC_DOC        : 'Document',
      LIST_FAILED        : 'Failed to load list',
      NO_DOCS_NEWEST     : 'No newest-version documents found',
      NO_DOCUMENTS_FOUND : 'No documents found',
      PRESIGN_FAILED     : 'Could not fetch the document',
      APPROVED_DOC       : '{name} is approved',
      APPROVE_THANKS     : 'Thank you for your approval ✔',

      OTP_INVALID        : 'Invalid code',
      OTP_RESEND_FAILED  : 'Could not resend',

      /* Impersonation */
      IMPERSONATION_MODE       : 'Logged in as client',
      READ_ONLY                : 'Read Only',
      IMPERSONATION_ERROR_TITLE: 'Access Link Error',
      IMPERSONATION_ERROR_HINT : 'Access links can only be used once. This link has already been used.',

      /* sidebar */
      SIDEBAR_PENDING  : 'Pending',
      SIDEBAR_APPROVED : 'Approved',
      APPROVE_ALL_BTN  : 'Approve all',

      /* empty states */
      PENDING_EMPTY  : 'There are no more documents awaiting your approval.',
      APPROVED_EMPTY : 'No documents have been approved yet.',

      /* viewer buttons */
      INTRO_BTN     : 'Watch 60-second intro video',
      DOWNLOAD_BTN  : 'Download PDF',
      PRINT_BTN     : 'Print PDF',
      PDF_VIEWER_TIP: 'Having trouble viewing the PDF? Click "Download PDF" to open it in a separate PDF viewer.',

      /* modal buttons & text */
      MODAL_CANCEL      : 'Cancel',
      MODAL_APPROVE     : 'Approve',
      MODAL_APPROVE_ALL : 'Approve all documents',
      MODAL_APPROVE_TXT : 'When you click <strong>Approve</strong>, you confirm that you are fully satisfied with the content of',
      MODAL_APPROVE_ALL_TXT : 'When you click <strong>Approve all documents</strong>, you confirm that you are fully satisfied with the content of the following documents:',

      /* success text */
      SUCCESS_PREFIX : '• ',
      APPROVE_PREFIX : 'Approve',
      
      /* blocked approval */
      BLOCKED_APPROVAL_HEADER : 'Document cannot be approved',
      BLOCKED_APPROVAL_BODY : 'Your lawyer has disabled the ability to approve this document, as some information is still required, before you can submit your final approval. If you\'re still in doubt about what\'s missing, after reading through your document, please use the chat on the right side, to contact us.',
      APPROVAL_BLOCKED_HINT : 'Cannot be approved yet. Information missing.',
      APPROVAL_BLOCKED_TOOLTIP : 'Cannot be approved yet. Information missing.',
      CLOSE : 'Close',

      /* chat */
      CHAT_HEADER       : 'Chat',
      CHAT_HEADER_OPEN  : 'Write to us',
      CHAT_PLACEHOLDER  : 'Write here…',
      CHAT_NO_MESSAGES  : 'No messages yet.',
      CHAT_LABEL        : 'Write to us here',
      CHAT_DISCLAIMER   : 'This chat is not live. We aim to reply within 5 business days.',
      CHAT_EMPTY        : 'No messages yet. Send a message to start the conversation.',
      CHAT_NO_DOC_WARNING: 'Please open a document first to see related messages.',

      /* intro modal */
      INTRO_TITLE : 'Welcome to your document portal',
      INTRO_H3A   : 'What happens now?',
      INTRO_P1    : `
        <ul>
          <li>You should now read through the documents carefully.</li>
          <li>If something is marked in red, it means we are missing some information.</li>
          <li>If you have any corrections or questions, you can write to the lawyer in the chat at the bottom right.</li>
          <li>You can also say you would like a call, and the lawyer will call you to agree on a time and date.</li>
        </ul>
      `,
      INTRO_H3B   : 'How to approve the documents',
      INTRO_P2    : `
        <ul>
          <li>On the left, you can click each document.</li>
          <li>If there are no more corrections or questions and nothing is marked in red, click the <strong>Approve</strong> button and that document will be approved.</li>
          <li>When all documents have been approved, emails will be sent with the final processes so you know exactly what to do next.</li>
        </ul>
      `,
      INTRO_CLOSE_BTN : 'Close and view documents',

      /* FAQ */
      FAQ_BTN       : 'Frequently Asked Questions',
      FAQ_TITLE     : 'Frequently Asked Questions',
      FAQ_CLOSE_BTN : 'Close',
      FAQ_SECTION1  : 'Will',
      FAQ_SECTION2  : 'Future Power of Attorney',
      FAQ_SECTION3  : 'Prenuptial Agreement',
      FAQ_SECTION4  : 'General Power of Attorney',

      FAQ_SECTION1_BODY : `
        <div class="faq-block">
          <h4>Grave maintenance</h4>
          <p>This clause allows your heirs to deduct the cost of a grave site <strong>tax-free</strong> from the estate. It is an option—not a requirement.</p>
        </div>

        <div class="faq-block">
          <h4>What are the forced share and the free share?</h4>
          <p>The <strong>forced share</strong> is 25% of the estate and must go to the spouse and lineal heirs.</p>
          <ul>
            <li>Spouse: 12.5%</li>
            <li>Lineal heirs (children/grandchildren): 12.5% shared</li>
          </ul>
          <p>The <strong>free share</strong> is 75%, which you may distribute freely in your will.</p>
          <p>If there is no spouse or lineal heirs, you effectively have 100% free share.</p>
        </div>

        <div class="faq-block">
          <h4>I heard about a 6.25% forced share—what is that?</h4>
          <p>The total forced share is 25%. The figure <strong>6.25%</strong> can arise in a scenario with <em>spouse (12.5%) and two children</em> who split 12.5% = <strong>6.25% per child</strong>. Percentages differ with more/fewer children or no spouse.</p>
        </div>

        <div class="faq-block">
          <h4>What is a “management department”?</h4>
          <p>When assets are tied up (entailed), the probate court may appoint an <em>approved management department</em> (a bank unit authorised to manage such assets), e.g., Nordea, Danske Bank, Spar Nord.</p>
        </div>

        <div class="faq-block">
          <h4>Succession order (explained)</h4>
          <p>“Succession order” is the sequence of heirs if there is still inheritance remaining when one heir dies. Example: a child inherits → then passes away → a grandchild inherits the remainder → then great-grandchild, and so on.</p>
        </div>

        <div class="faq-block">
          <h4>Pensions and insurances</h4>
          <p>These are generally <strong>not</strong> governed by the will but by beneficiary designations with the providers. Contact the providers to see and change designations. In some cases, payouts may become part of the estate and then follow the will.</p>
        </div>
      `,

      FAQ_SECTION2_BODY : `
        <div class="faq-block">
          <h4>Why does XXXX replace the last 4 digits of the CPR number?</h4>
          <p>Future powers of attorney are registered in the <strong>Land Register</strong> (Tingbogen), a public system. People are registered with their full CPR, but the last four digits are hidden on the document for privacy.</p>
        </div>

        <div class="faq-block">
          <h4>§ 7.2 – Annual accounts</h4>
          <p>This is a <strong>legal requirement</strong> and cannot be avoided. No auditor is required; a <em>bank statement with vouchers</em> for each transaction is sufficient for the Family Court to supervise.</p>
        </div>

        <div class="faq-block">
          <h4>§ 12.1 – Can I get a guardian even if I have a future power of attorney?</h4>
          <p>Only if <strong>all</strong> appointed attorneys cannot or will not act. In that case, the Family Court appoints a <em>professional guardian</em> so your interests are still looked after.</p>
        </div>
      `,

      FAQ_SECTION3_BODY : `
        <p>Content coming soon. If you have questions about prenuptial agreements now, please write in the chat and we’ll help.</p>
      `,

      FAQ_SECTION4_BODY : `
        <div class="faq-block">
          <h4>Difference between general and future power of attorney</h4>
          <p>A <strong>general power of attorney</strong> is used while you still have full capacity but need help with everyday matters due to age/illness. It is useful—especially in the period <em>before</em> a future power might be activated.</p>
          <p>A <strong>future power of attorney</strong> applies when you <em>no longer</em> have capacity. It requires a medical certificate and activation via the Family Court. The process can take months—during which the general power “catches” you in the meantime.</p>
        </div>

        <div class="faq-block">
          <h4>Why is there only one person on my general power of attorney?</h4>
          <p>Typically <strong>one</strong> attorney is named to avoid uncertainty about who may act. This keeps the process simpler and clearer for banks and authorities.</p>
          <p>It is possible to <strong>transfer</strong> the general power to another person if the document permits it. This will be stated (often in sections 2–3). Only you, as the grantor, can decide such a transfer.</p>
        </div>
      `,

      /* post-approval modal */
      POST_APPROVAL_TITLE : 'All documents are approved',
      POST_APPROVAL_H3A   : 'Thank you for your approval',
      POST_APPROVAL_P1    : `
        <p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Suspendisse id lectus non justo tempus accumsan.</p>
      `,
      POST_APPROVAL_H3B   : 'What happens now?',
      POST_APPROVAL_P2    : `
        <p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Quisque placerat, neque sed facilisis cursus, tortor lacus consequat leo, vitae tincidunt metus nulla sed neque.</p>
      `,
      POST_APPROVAL_CLOSE_BTN : 'Close',
      POST_APPROVAL_VIEW_BTN  : 'View receipt',

      /* tour (in-app guidance) */
      TOUR_CLOSE        : 'Close guide',
      TOUR_BACK         : 'Back',
      TOUR_NEXT         : 'Next',
      TOUR_DONE         : 'Understood',
      TOUR_STEP_SIDEBAR : 'Here you can see a list of your documents – try clicking on one!',
      TOUR_STEP_FAQ     : 'Here you can find answers to the most common questions',
      TOUR_STEP_PDF     : 'Here you can see the document content. Read it through and make sure everything is as you want it.',
      TOUR_STEP_CHAT    : 'If you have any questions, you can write to us here. We reply within 3-5 working days – often faster!',
      TOUR_STEP_APPROVE : 'When you are satisfied, click “Approve”.',
      TOUR_STEP_DOWNLOAD: 'Use these buttons to download or print the document as a PDF.',
      TOUR_RELAUNCH     : 'Restart guide',

      /* footer */
      FOOTER_TEXT : '&copy; 2025 Heres Law • Need help? <a href="mailto:support@hereslaw.ie">support@hereslaw.ie</a>',

      /* fallback */
      MISSING : '[MISSING TEXT]'
    }
  };

  // Global translator with safe fallback to Danish + console warning on misses
  window._t = function(key){
    const lang =
      (window.__BRAND && window.__BRAND.lang) ||
      (document.documentElement && document.documentElement.lang) ||
      'da';

    const dict = DICTS[lang] || DICTS.da;

    if (key in dict) {
      const value = dict[key];
      // Handle nested objects with language keys (e.g. {da: ".", sv: ".", en: "."})
      if (typeof value === 'object' && value !== null && !Array.isArray(value)) {
        return value[lang] || value.da || value.en || '[MISSING TEXT]';
      }
      return value;
    }

    // ← Change is here: when falling back to DA, prefer value[lang] if present
    if (key in DICTS.da) {
      console.warn(`texts.js → missing "${key}" in locale: ${lang} (falling back to da)`);
      const value = DICTS.da[key];
      if (typeof value === 'object' && value !== null && !Array.isArray(value)) {
        return value[lang] || value.da || value.en || '[MISSING TEXT]';
      }
      return value;
    }

    console.warn(`texts.js → missing key: ${key}`);
    return DICTS.da.MISSING || '[MISSING TEXT]';
  };

})();
