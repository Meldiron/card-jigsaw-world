"""Keyword filters (people, text-heavy, unwanted media) and the image rules."""
import re

PEOPLE = """person people human humans man men woman women boy boys girl girls child children kid kids baby babies toddler
infant teen teenager adult face faces selfie portrait self-portrait bride groom wedding couple family families
crowd crowds tourist tourists visitor visitors hiker hikers climber climbers swimmer swimmers surfer surfers
skier skiers snowboarder cyclist cyclists rider riders runner runners jogger dancer dancers ballerina player
players athlete athletes soldier soldiers farmer farmers fisherman fishermen chef chefs monk monks priest nun
nuns pilgrim figure figures nude nudes gentleman gentlemen grandmother grandfather grandma grandpa brother
sister student students teacher teachers doctor doctors astronaut astronauts sailor sailors vendor vendors
seller merchant shopper shoppers pedestrian pedestrians passenger passengers audience spectator spectators
musician musicians singer guitarist busker performer performers actor actress wedding bridesmaid yoga
meditation silhouette silhouettes hand hands bodybuilder fitness workout jogging hiking selfie smiling smile
laughing portraits madonna apostle apostles christ jesus cherub putti nymph warrior warriors knight knights
peasant peasants bather bathers odalisque lovers girlfriend boyfriend policeman police officer officers
firefighter firefighters veteran veterans protest protesters parade festival-goers party guests guest cosplay
costume costumes mannequin statue-of-person""".split()
PEOPLE_RE = re.compile(r'\b(' + '|'.join(re.escape(w) for w in PEOPLE) + r')\b', re.I)

TEXT = """text texts sign signs signage poster posters placard document documents manuscript manuscripts page pages
letter letters newspaper newspapers magazine inscription inscriptions plaque plaques label labels menu menus
calligraphy typography font fonts banner banners billboard billboards logo logos flyer flyers leaflet
certificate chart charts diagram diagrams infographic screenshot screenshots scan scanned title-page
advertisement advertising advert ads stamp stamps postage banknote banknotes coin coins currency ticket
tickets receipt handwriting handwritten notebook book-page bookpage lettering graffiti-text slogan quote
quotes headline table-of-contents blueprint sheet-music scoreboard""".split()
TEXT_RE = re.compile(r'\b(' + '|'.join(re.escape(w) for w in TEXT) + r')\b', re.I)

UNWANTED = """clipart clip-art icon icons emoji vector svg logo diagram wiring circuit schematic xray x-ray mri microscope
histology pathology wound injury surgery corpse dead skull funeral grave graves cemetery weapon gun rifle
pistol war battle military missile nazi swastika flag-burning porn sexy lingerie bikini""".split()
UNWANTED_RE = re.compile(r'\b(' + '|'.join(re.escape(w) for w in UNWANTED) + r')\b', re.I)

MIN_SHORT_HARD = 640      # reject below this (CMA web renditions are ~700 wide)
MIN_SHORT_WANT = 900      # new candidates should reach this
MIN_COUNT = 20
TARGET_COUNT = 24

def keyword_flags(text, allow=()):
    """Return a set of reasons found in text: people / text / unwanted."""
    text = (text or '').lower()
    reasons = set()
    m = [w for w in PEOPLE_RE.findall(text) if w.lower() not in allow]
    if m: reasons.add('people:' + ','.join(sorted(set(x.lower() for x in m))[:4]))
    m = [w for w in TEXT_RE.findall(text) if w.lower() not in allow]
    if m: reasons.add('text:' + ','.join(sorted(set(x.lower() for x in m))[:4]))
    m = [w for w in UNWANTED_RE.findall(text) if w.lower() not in allow]
    if m: reasons.add('unwanted:' + ','.join(sorted(set(x.lower() for x in m))[:4]))
    return reasons

def size_flags(w, h, min_short=MIN_SHORT_WANT):
    reasons = set()
    if not w or not h:
        reasons.add('unreadable'); return reasons
    if w > h: reasons.add('landscape')
    if min(w, h) < MIN_SHORT_HARD: reasons.add('too-small')
    elif min(w, h) < min_short: reasons.add('small')
    return reasons

def licence_ok(short):
    """Accept only free licences that allow commercial use and derivatives."""
    s = (short or '').strip().lower()
    if not s: return False
    if 'nc' in s.replace('once', '') and 'cc' in s: return False
    if 'nd' in s and 'cc' in s: return False
    if s.startswith(('cc0', 'cc-0', 'cc zero', 'public domain', 'pd', 'no restrictions', 'copyrighted free use',
                     'cc by', 'cc-by', 'attribution', 'pdm', 'by', 'by-sa', 'cc by-sa', 'public')):
        return True
    return False
