package harddrake::v4l;

use strict;

use common;
use detect_devices;
use log;
use modules;

# please update me on bttv update :

my $default = N("Auto-detect");
# TODO: split %tuners_lst in per driver perl source files that get transformed in Storable files
my %tuners_lst = 
    (
     -1 => $default,
     0 => "Temic|PAL (4002 FH5)",
     1 => "Philips|PAL_I (FI1246 and compatibles)",
     2 => "Philips|NTSC (FI1236, FM1236 and compatibles)",
     3 => "Philips|(SECAM+PAL_BG) (FI1216MF, FM1216MF, FR1216MF)",
     4 => "NoTuner",
     5 => "Philips|PAL_BG (FI1216 and compatibles)",
     6 => "Temic|NTSC (4032 FY5)",
     7 => "Temic|PAL_I (4062 FY5)",
     8 => "Temic|NTSC (4036 FY5)",
     9 => "Alps|HSBH1",
     10 => "Alps|TSBE1",
     11 => "Alps|TSBB5",
     12 => "Alps|TSBE5",
     13 => "Alps|TSBC5",
     14 => "Temic|PAL_BG (4006FH5)",
     15 => "Alps|TSCH6",
     16 => "Temic|PAL_DK (4016 FY5)",
     17 => "Philips|NTSC_M (MK2)",
     18 => "Temic|PAL_I (4066 FY5)",
     19 => "Temic|PAL* auto (4006 FN5)",
     20 => "Temic|PAL_BG (4009 FR5) or PAL_I (4069 FR5)",
     21 => "Temic|NTSC (4039 FR5)",
     22 => "Temic|PAL/SECAM multi (4046 FM5)",
     23 => "Philips|PAL_DK (FI1256 and compatibles)",
     24 => "Philips|PAL/SECAM multi (FQ1216ME)",
     25 => "LG|PAL_I+FM (TAPC-I001D)",
     26 => "LG|PAL_I (TAPC-I701D)",
     27 => "LG|NTSC+FM (TPI8NSR01F)",
     28 => "LG|PAL_BG+FM (TPI8PSB01D)",
     29 => "LG|PAL_BG (TPI8PSB11D)",
     30 => "Temic|PAL* auto + FM (4009 FN5)",
     31 => "SHARP NTSC_JP (2U5JF5540)",
     32 => "Samsung|PAL TCPM9091PD27",
     33 => "MT20xx universal",
     34 => "Temic|PAL_BG (4106 FH5)",
     35 => "Temic|PAL_DK/SECAM_L (4012 FY5)",
     36 => "Temic|NTSC (4136 FY5)",
     37 => "LG|PAL (newer TAPC series)",
     38 => "Philips|PAL/SECAM multi (FM1216ME)",
     39 => "LG|NTSC (newer TAPC series)",
     40 => "HITACHI V7-J180AT",
     41 => "Philips|PAL_MK (FI1216 MK)",
     42 => "Philips|1236D ATSC/NTSC daul in",
     43 => "Philips|NTSC MK3 (FM1236MK3 or FM1236/F)",
     44 => "Philips|4 in 1 (ATI TV Wonder Pro/Conexant)",
     45 => "Microtune|4049 FM5",
     46 => "Panasonic VP27s/ENGE4324D",
     47 => "LG|NTSC (TAPE series)",
     48 => "Tena|TNF 8831 BGFF",
     49 => "Microtune|4042 FI5 ATSC/NTSC dual in",
     50 => "TCL 2002N",
     51 => "Philips|PAL/SECAM_D (FM 1256 I-H3)",
     52 => "Thomson|DDT 7610 (ATSC/NTSC)",
     53 => "Philips|FQ1286",
     54 => "tda8290+75",
     55 => "LG|PAL (TAPE series)",
     56 => "Philips|PAL/SECAM multi (FQ1216AME MK4)",
     57 => "Philips|FQ1236A MK4",
     58 => "Ymec|TVision|TVF-8531MF",
     59 => "Ymec|TVision|TVF-5533MF",
     60 => "Thomson|DDT 7611 (ATSC/NTSC)",
     61 => "Tena|TNF9533-D/IF/TNF9533-B/DF",
     62 => "Philips|TEA5767HN FM Radio",
     63 => "Philips|FMD1216ME MK3 Hybrid Tuner",
     64 => "LG|TDVS-H062F/TUA6034",
     65 => "Ymec|TVF66T5-B/DFF",
     66 => "LG|NTSC (TALN mini series)",
     67 => "Philips|TD1316 Hybrid Tuner",
     68 => "Philips|TUV1236D ATSC/NTSC dual in",
     69 => "Tena|TNF 5335 MF",
     70 => "Samsung|TCPN 2121P30A",

     );

# Tweaked from Cardlist
my $cards_lst = {
    'bttv' => {
        $default => -1,
        N("Unknown|Generic") => 0,
        "M|Miro|PCTV" => 1,
        "H|Hauppauge|bt848" => 2,
        "S|STB|Hauppauge 878" => 3,
        "I|Intel|Create and Share PCI (bttv type 4)" => 4,
        "I|Intel|Smart Video Recorder III (bttv type 4)" => 4,
        "D|Diamond DTV2000" => 5,
        "A|AVerMedia|TVPhone" => 6,
        "M|MATRIX Vision|MV-Delta" => 7,
        "L|Lifeview|FlyVideo II (Bt848) LR26" => 8,
        "G|Guillemot|MAXI TV Video PCI2 LR26" => 27,
        "G|Genius/Kye Video Wonder Pro II (848 or 878)" => 8,
        "I|IMS/IXmicro TurboTV" => 9,
        "H|Hauppauge|bt878" => 10,
        "M|Miro|PCTV pro" => 11,
        "A|ADS Technologies|Channel Surfer TV (bt848)" => 12,
        "A|AVerMedia|TVCapture 98" => 13,
        "A|Aimslab|Video Highway Xtreme (VHX)" => 14,
        "Zoltrix|TV-Max" => 15,
        "P|Prolink|Pixelview PlayTV (bt878)" => 16,
        "L|Leadtek|WinView 601" => 17,
        "A|AVEC|Intercapture" => 18,
        "L|Lifeview|FlyKit LR38 Bt848 (capture only)" => 19,
        "L|Lifeview|FlyVideo II EZ" => 19,
        "C|CEI Raffles Card" => 20,
        "L|Lifeview|FlyVideo 98" => 21,
        "L|Lucky Star Image World ConferenceTV LR50" => 21,
        "A|Askey|CPH050" => 22,
        "P|Phoebe Micro|Tv Master + FM" => 22,
        "M|Modular|Technology MM205 PCTV (bt878)" => 23,
        "A|Askey|CPH06X (bt878)" => 24,
        "G|Guillemot|Maxi TV Video 3" => 24,
        "A|Askey|CPH05X (bt878)" => 24,
        N("Unknown|CPH05X (bt878) [many vendors]") => 24,
        N("Unknown|CPH06X (bt878) [many vendors]") => 24,
        "T|Terratec|Terra TV+ Version 1.0 (Bt848)" => 25,
        "V|Vobis TV-Boostar" => 25,
        "T|Terratec|TV-Boostar" => 25,
        "H|Hauppauge|WinCam newer (bt878)" => 26,
        "L|Lifeview|FlyVideo 98" => 27,
        "G|Guillemot|MAXI TV Video PCI2 LR50" => 27,
        "T|Terratec|TerraTV+" => 28,
        "I|Imagenation PXC200" => 29,
        "L|Lifeview|FlyVideo 98 LR50" => 30,
        "Formac|iProTV" => 31,
        "Formac|iProTV I (bt848)" => 31,
        "I|Intel|Create and Share PCI (bttv type 32)" => 32,
        "I|Intel|Smart Video Recorder III (bttv type 32)" => 32,
        "T|Terratec|TerraTValue" => 33,
        "L|Leadtek|WinFast TV 2000" => 34,
        "L|Leadtek|WinFast VC 100" => 35,
        "L|Lifeview|FlyVideo 98 LR50" => 35,
        "C|Chronos Video Shuttle II" => 35,
        "L|Lifeview|FlyVideo 98FM LR50" => 36,
        "T|Typhoon|TView TV/FM Tuner" => 36,
        "P|Prolink|PixelView PlayTV pro" => 37,
        "P|Prolink|PixelView PlayTV Theater" => 37,
        "A|Askey|CPH06X TView99" => 38,
        "P|Pinnacle|PCTV Studio/Rave" => 39,
        "S|STB|STB2 TV PCI FM, P/N 6000704" => 40,
        "A|AVerMedia|TVPhone 98" => 41,
        "P|ProVideo|PV951" => 42,
        "L|Little OnAir TV" => 43,
        "S|Sigma TVII-FM" => 44,
        "M|MATRIX Vision|MV-Delta 2" => 45,
        "Zoltrix|Genie TV/FM" => 46,
        "T|Terratec|TV/Radio+" => 47,
        "A|Askey|CPH03x" => 48,
        "D|Dynalink Magic TView" => 48,
        "I|IODATA|GV-BCTV3/PCI" => 49,
        "P|Prolink|PixelView PlayTV PAK" => 50,
        "L|Lenco|MXTV-9578 CP" => 50,
        "P|Prolink|PV-BT878P+4E" => 50,
        "L|Lenco|MXTV-9578CP (Bt878)" => 50,
        "E|Eagle Wireless Capricorn2 (bt878A)" => 51,
        "P|Pinnacle|PCTV Studio Pro" => 52,
        "T|Typhoon|KNC1 TV Station RDS" => 53,
        "T|Typhoon|TV Tuner RDS (black package)" => 53,
        "T|Typhoon|TView RDS + FM Stereo" => 53,
        "L|Lifeview|FlyVideo 2000" => 54,
        "L|Lifeview|FlyVideo A2" => 54,
        "L|Lifetec|LT 9415 TV [LR90]" => 54,
        "A|Askey|CPH031" => 55,
        "L|Lenco|MXR-9571 (Bt848)" => 55,
        "Bestbuy|Easy TV" => 55,
        "L|Lifeview|FlyVideo 98FM LR50" => 56,
        "G|GrandTec|Grand Video Capture (Bt848)" => 57,
        "A|Askey|CPH060" => 58,
        "P|Phoebe Micro|TV Master Only (No FM)" => 58,
        "A|Askey|CPH03x TV Capturer" => 59,
        "M|Modular|Technology MM100 PCTV" => 60,
        "A|AG|Electronics GMV1" => 61,
        "A|Askey|CPH061" => 62,
        "Bestbuy|Easy TV (bt878)" => 62,
        "L|Lifetec|LT9306" => 62,
        "M|Medion MD9306" => 62,
        "A|ATI|TV-Wonder" => 63,
        "A|ATI|TV-Wonder VE" => 64,
        "L|Lifeview|FlyVideo 2000S LR90" => 65,
        "T|Terratec|TValueRadio" => 66,
        "I|IODATA|GV-BCTV4/PCI" => 67,
        "3Dfx|VoodooTV FM (Euro)" => 68,
        "3Dfx|VoodooTV 200 (USA)" => 68,
        "A|Active|Imaging AIMMS" => 69,
        "P|Prolink|Pixelview PV-BT878P+ (Rev.4C)" => 70,
        "L|Lifeview|FlyVideo 98EZ (capture only) LR51" => 71,
#    "G|Genius/Kye|Video Wonder/Genius Internet Video Kit" => 71,
        "P|Prolink|Pixelview PV-BT878P+ (Rev.9B) (PlayTV Pro rev.9B FM+NICAM)" => 72,
        "T|Typhoon|TV Tuner Pal BG (blue package)" => 72,
        "S|Sensoray 311" => 73,
        "RemoteVision|MX (RV605)" => 74,
        "P|Powercolor|MTV878" => 75,
        "P|Powercolor|MTV878R" => 75,
        "P|Powercolor|MTV878F" => 75,
        "C|Canopus WinDVR PCI (COMPAQ Presario 3524JP, 5112JP)" => 76,
        "G|GrandTec|Multi Capture Card (Bt878)" => 77,
        "Jetway TV/Capture JW-TV878-FBK" => 78,
        "K|Kworld KW-TV878RF" => 78,
        "D|DSP Design TCVIDEO" => 79,
        "H|Hauppauge|WinTV PVR" => 80,
        "G|GV-BCTV5/PCI" => 81,
        "Osprey|100/150 (878)" => 82,
        "Osprey|100/150 (848)" => 83,
        "Osprey|101 (848)" => 84,
        "Osprey|101/151" => 85,
        "Osprey|101/151 w/ svid" => 86,
        "Osprey|200/201/250/251" => 87,
        "Osprey|200/250" => 88,
        "Osprey|210/220" => 89,
        "Osprey|500" => 90,
        "Osprey|540" => 91,
        "Osprey|2000" => 92,
        "I|IDS Eagle" => 93,
        "P|Pinnacle|PCTV Sat" => 94,
        "Formac|ProTV II (bt878)" => 95,
        "M|MachTV" => 96,
        "E|Euresys|Picolo" => 97,
        "P|ProVideo|PV150" => 98,
        "A|AD-TVK503" => 99,
        "H|Hercules Smart TV Stereo" => 100,
        "P|Pace TV & Radio Card" => 101,
        "I|IVC|200" => 102,
        "G|GrandTec|Grand X-Guard / Trust 814PCI" => 103,
        "N|Nebula Electronics DigiTV" => 104,
        "P|ProVideo|PV143" => 105,
        "P|PHYTEC|VD-009-X1 MiniDIN (bt878)" => 106,
        "P|PHYTEC|VD-009-X1 Combi (bt878)" => 107,
        "P|PHYTEC|VD-009 MiniDIN (bt878)" => 108,
        "P|PHYTEC|VD-009 Combi (bt878)" => 109,
        "I|IVC|100" => 110,
        "I|IVC|120G" => 111,
        "P|pcHDTV HD-2000 TV" => 112,
        "T|Twinhan DST + clones" => 113,
        "L|Leadtek|Winfast VC100" => 114,
        "T|Teppro TEV-560/InterVision IV-560" => 115,
        "S|SIMUS GVC1100" => 116,
        "N|NGS NGSTV+" => 117,
        "L|LMLBT4" => 118,
        "T|Tekram M205 PRO" => 119,
        "C|Conceptronic|CONTVFMi" => 120,
        "E|Euresys|Picolo Tetra" => 121,
        "S|Spirit TV Tuner" => 122,
        "A|AverMedia|AVerTV DVB-T 771" => 123,
        "A|AverMedia|AverTV DVB-T 761" => 124,
        "M|MATRIX Vision|Sigma-SQ" => 125,
        "M|MATRIX Vision|Sigma-SLC" => 126,
        "A|APAC Viewcomp 878(AMAX)" => 127,
        "D|DViCO|FusionHDTV DVB-T Lite" => 128,
        "V|V-Gear MyVCD" => 129,
        "S|Super TV Tuner" => 130,
        "T|Tibet Systems 'Progress DVR' CS16" => 131,
        "K|Kodicom|4400R (master)" => 132,
        "K|Kodicom|4400R (slave)" => 133,
        "A|Adlink|RTV24" => 134,
        "D|DViCO|FusionHDTV 5 Lite" => 135,
        "A|Acorp|Y878F" => 136,
        "C|Conceptronic|CTVFMi v2" => 137,
        "P|Prolink|Pixelview PV-BT878P+ (Rev.2E)" => 138,
        "P|Prolink|PixelView PlayTV MPEG2 PV-M4900" => 139,
        "Osprey|440" => 140,
        "A|Asound|Skyeye PCTV" => 141,
        "S|Sabrent TV-FM (bttv version)" => 142,
        "H|Hauppauge|ImpactVCB (bt878)" => 143,
        "M|MagicTV" => 144,

    },
    
    'cx88' => {
        N("Unknown|Generic") => 0,
        "Hauppauge|WinTV 34xxx models" => 1,
        "GDI Black Gold" => 2,
        "PixelView|???" => 3,
        "ATI|TV Wonder Pro" => 4,
        "Leadtek|Winfast 2000XP Expert" => 5,
        "AVerTV|Studio 303 (M126)               " => 6,
        'MSI|TV-@nywhere Master' => 7,
        "Leadtek|Winfast DV2000" => 8,
        "Leadtek|PVR 2000" => 9,
        "IODATA|GV-VCP3/PCI" => 10,
        "Prolink PlayTV PVR" => 11,
        "ASUS PVR-416" => 12,
        'MSI|TV-@nywhere' => 13,
        "VStream|XPert DVB-T" => 14,
        "KWorld|XPert DVB-T" => 14,
        "DViCO|FusionHDTV DVB-T1" => 15,
        "KWorld|LTV883RF" => 16,
        "DViCO|FusionHDTV 3 Gold" => 17,
        "Hauppauge|Nova-T DVB-T" => 18,
        "Conexant DVB-T reference design" => 19,
        "Provideo PV259" => 20,
        "DViCO|FusionHDTV DVB-T Plus" => 21,
        "digitalnow|DNTV Live! DVB-T" => 22,
        "pcHDTV HD3000 HDTV" => 23,
        "Hauppauge|WinTV 28xxx (Roslyn) models" => 24,
        "Digital-Logic MICROSPACE Entertainment Center (MEC)" => 25,
        "IODATA|GV/BCTV7E" => 26,
        "PixelView|PlayTV Ultra Pro (Stereo)" => 27,
        "DViCO|FusionHDTV 3 Gold-T" => 28,
        "ADS Tech Instant TV DVB-T PCI" => 29,
        "TerraTec Cinergy 1400 DVB-T" => 30,
        "DViCO|FusionHDTV 5 Gold" => 31,
        "AverMedia UltraTV Media Center PCI 550" => 32,
        "KWorld|V-Stream Xpert DVD" => 33,
        "ATI|HDTV Wonder" => 34,
        "WinFast DTV1000-T" => 35,
        "AVerTV|303 (M126)" => 36,
        "Hauppauge|Nova-S-Plus DVB-S" => 37,
        "Hauppauge|Nova-SE2 DVB-S" => 38,
        "KWorld|VB-S 100" => 39,
        "Hauppauge|WinTV-HVR1100 DVB-T/Hybrid" => 40,
        "Hauppauge|WinTV-HVR1100 DVB-T/Hybrid (Low Profile)  [0070:9800,0070:9802]" => 41,
        "digitalnow|DNTV Live! DVB-T Pro" => 42,
        "VStream|XPert DVB-T with cx22702" => 43,
        "KWorld|XPert DVB-T with cx22702" => 43,
        "DViCO|FusionHDTV DVB-T Dual Digital" => 44,

    },

    'saa7134' => {
        N("Unknown|Generic") => 0,
        "Proteus Pro [philips reference design]" => 1,
        "LifeView|FlyVIDEO3000" => 2,
        "LifeView|FlyVIDEO2000" => 3,
        "EMPRESS" => 4,
        "SKNet|Monster TV" => 5,
        "Tevion|MD 9717" => 6,
        "KNC|One TV-Station RDS" => 7,
        "Typhoon|TV Tuner RDS" => 7,
        "Terratec|Cinergy 400 TV" => 8,
        "Medion|5044" => 9,
        "Kworld|SAA7130-TVPCI" => 10,
        "KuroutoShikou SAA7130-TVPCI" => 10,
        "Terratec|Cinergy 600 TV" => 11,
        "Medion|7134" => 12,
        "Typhoon|TV+Radio 90031" => 13,
        "ELSA|EX-VISION 300TV" => 14,
        "ELSA|EX-VISION 500TV" => 15,
        "ASUS|TV-FM 7134" => 16,
        "AOPEN VA1000 POWER" => 17,
        "BMK|MPEX No Tuner" => 18,
        "Compro|VideoMate TV" => 19,
        "Matrox CronosPlus" => 20,
        "10MOONS PCI TV CAPTURE CARD" => 21,
        "Medion|2819" => 22,
        "AverMedia|M156" => 22,
        "BMK|MPEX Tuner" => 23,
        "KNC|One TV-Station DVR" => 24,
        "ASUS|TV-FM 7133" => 25,
        "Pinnacle|PCTV Stereo (saa7134)" => 26,
        "Manli|MuchTV M-TV002/Behold TV 403 FM" => 27,
        "Manli|MuchTV M-TV001/Behold TV 401" => 28,
        "Nagase Sangyo TransGear 3000TV" => 29,
        "Elitegroup|ECS TVP3XP FM1216 Tuner Card(PAL-BG,FM)" => 30,
        "Elitegroup|ECS TVP3XP FM1236 Tuner Card (NTSC,FM)" => 31,
        "AVACS SmartTV" => 32,
        "AverMedia|DVD EZMaker" => 33,
        "Noval Prime TV 7133" => 34,
        "AverMedia|AverTV Studio 305" => 35,
        "UPMOST PURPLE TV" => 36,
        "Items MuchTV Plus / IT-005" => 37,
        "Terratec|Cinergy 200 TV" => 38,
        "LifeView|FlyTV Platinum Mini" => 39,
        "Compro|VideoMate TV PVR/FM" => 40,
        "Compro|VideoMate TV Gold+" => 41,
        "Sabrent SBT-TVFM (saa7130)" => 42,
        "Zolid Xpert TV7134" => 43,
        "Empire PCI TV-Radio LE" => 44,
        "AverMedia|AVerTV Studio 307" => 45,
        "AverMedia|Cardbus TV/Radio" => 46,
        "Terratec|Cinergy 400 mobile" => 47,
        "Terratec|Cinergy 600 TV MK3" => 48,
        "Compro|VideoMate Gold+ Pal" => 49,
        "Pinnacle|PCTV 300i DVB-T + PAL" => 50,
        "ProVideo PV952" => 51,
        "AverMedia|AverTV/305" => 52,
        "ASUS|TV-FM 7135" => 53,
        "LifeView|FlyTV Platinum FM" => 54,
        "LifeView|FlyDVB-T DUO" => 55,
        "AverMedia|AVerTV 307" => 56,
        "AverMedia|AVerTV GO 007 FM" => 57,
        "ADS Tech Instant TV (saa7135)" => 58,
        "Kworld|V-Stream Xpert TV PVR7134" => 59,
        "Tevion|V-Stream Xpert TV PVR7134" => 59,
        "Typhoon|DVB-T Duo Digital/Analog Cardbus" => 60,
        "Philips|TOUGH DVB-T reference design" => 61,
        "Compro|VideoMate TV Gold+II" => 62,
        "Kworld|Xpert TV PVR7134" => 63,
        "FlyTV mini Asus Digimatrix" => 64,
        "Kworld|V-Stream Studio TV Terminator" => 65,
        "Yuan TUN-900 (saa7135)" => 66,
        "Beholder BeholdTV 409 FM" => 67,
        "GoTView 7135 PCI" => 68,
        "Philips|EUROPA V3 reference design" => 69,
        "Compro|Videomate DVB-T300" => 70,
        "Compro|Videomate DVB-T200" => 71,
        "RTD|Embedded Technologies VFG7350" => 72,
        "RTD|Embedded Technologies VFG7330" => 73,
        "LifeView|FlyTV Platinum Mini2" => 74,
        "AverMedia|AVerTVHD MCE A180" => 75,
        "SKNet|MonsterTV Mobile" => 76,
        "Pinnacle|PCTV 110i (saa7133)" => 77,
        "ASUSTeK P7131 Dual" => 78,
        "Sedna/MuchTV PC TV Cardbus TV/Radio (ITO25 Rev:2B)" => 79,
        "ASUS|Digimatrix TV" => 80,
        "Philips|Tiger reference design" => 81,
        "MSI TV\@Anywhere plus" => 82,
        "Terratec|Cinergy 250 PCI TV" => 83,
        "LifeView|FlyDVB Trio" => 84,

    }
};

my %pll_lst = 
    (
     -1 => N("Default"),
     0 => "do not use pll",
     1 => "28 Mhz Crystal (X)",
     2 => "35 Mhz Crystal"
     );

sub config {
    my ($in, $modules_conf, $driver) = @_;

    my $min_gbuffers = 2;
    my $max_gbuffers = 32;

    my %conf = (gbuffers => 4, card => $default, tuner => -1, radio => 0, pll => -1);

    my %cards_list = %{$cards_lst->{$driver}};
    my %rvs_cards_list = reverse %cards_list;

    # get the existing options (if there are any)
    my $current = $modules_conf->get_options($driver);

    foreach (split(/\s+/,$current)) {
        $conf{$1} = $2 if /^(gbuffers|tuner|radio|pll)=(.+)/;
        $conf{$1} = $rvs_cards_list{$2} if /^(card)=(.+)/;
    }
    
    #Sanity checks on defaults
    $conf{gbuffers} = max($min_gbuffers, $conf{gbuffers});
    $conf{gbuffers} = min($max_gbuffers, $conf{gbuffers});
    $conf{card}  = $default if !defined $cards_list{$conf{card}};
    $conf{tuner} = -1 if !defined $tuners_lst{$conf{tuner}};
    if ($driver eq 'bttv') {
        $conf{pll}   = -1 if !defined $pll_lst{$conf{tuner}};
        $conf{radio} =  0 if $conf{radio} !~ /(0|1)/;
    }


    if ($in->ask_from("BTTV configuration", N("For most modern TV cards, the bttv module of the GNU/Linux kernel just auto-detect the rights parameters.
If your card is misdetected, you can force the right tuner and card types here. Just select your tv card parameters if needed."),
                      [
                       { label => N("Card model:"), val => \$conf{card}, list => [ keys %cards_list ], default => -1, sort =>1, separator => '|' },
                       { label => N("Tuner type:"), val => \$conf{tuner}, list => [keys %tuners_lst], format => sub { $tuners_lst{$_[0]} }, sort => 1, separator => '|' },
                       { label => N("Number of capture buffers:"), val => \$conf{gbuffers}, min => $min_gbuffers, max => $max_gbuffers, sort => 1, default => 0, type => 'range', advanced => 1, help => N("number of capture buffers for mmap'ed capture") },                    
                       if_($driver eq 'bttv',
                           { label => N("PLL setting:"), val => \$conf{pll}, list => [keys %pll_lst], format => sub { $pll_lst{$_[0]} }, sort => 1, default => 0, advanced =>1 },
                           { label => N("Radio support:"), val => \$conf{radio}, type => "bool", text => N("enable radio support") }),
                       ]
                      ))
    {
        $conf{card} = $cards_list{$conf{card}};
        if (my $options = join(' ', if_($driver eq 'bttv', 'radio=' . ($conf{radio} ? 1 : 0)), map { if_($conf{$_} ne -1, "$_=$conf{$_}") } qw(card pll tuner gbuffers))) {
            log::l(qq([harddrake::v4l] set "$options" options for $driver));
#             log::explanations("modified file /etc/modules.conf ($options)") if $::isStandalone;
              $modules_conf->set_options($driver, $options);
          }
        return 1;
    }
    return 0;
}



1;
