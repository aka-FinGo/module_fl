// ══════════════════════════════════════════════════════════════
//  CABIX KONVEYER — Apps Script Backend  v4.0
//  2 ta varaq: "Modullar" + "Furnituralar"
// ══════════════════════════════════════════════════════════════

const CONFIG = {
  MODULLAR_SHEET:  'Modullar',
  FURNITURA_SHEET: 'Furnituralar',
  BOT_TOKEN:       'SIZNING_BOT_TOKEN',  // ← o'zgartiring
  CHAT_ID:         '-100SIZNING_CHANNEL_ID',    // ← o'zgartiring
  PASSWORD:        'admin_PAROL',         // ← o'zgartiring
};

// Modullar: A=artikul B=nomi C=tgPdfId D=tgVideoId E=pdfUrl F=videoUrl
const M = { ARTIKUL:0, NOMI:1, TG_PDF:2, TG_VIDEO:3, PDF_URL:4, VIDEO_URL:5 };

// Furnituralar: A=artikul B=kategoriya C=nomi D=ulchov E=soni
const F = { ARTIKUL:0, KAT:1, NOMI:2, ULCHOV:3, SONI:4 };

function getModullarSheet() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sh = ss.getSheetByName(CONFIG.MODULLAR_SHEET);
  if (!sh) {
    sh = ss.insertSheet(CONFIG.MODULLAR_SHEET);
    sh.getRange(1,1,1,6).setValues([['artikul','nomi','tgPdfId','tgVideoId','pdfUrl','videoUrl']]);
    sh.getRange(1,1,1,6).setFontWeight('bold');
  }
  return sh;
}

function getFurnituraSheet() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sh = ss.getSheetByName(CONFIG.FURNITURA_SHEET);
  if (!sh) {
    sh = ss.insertSheet(CONFIG.FURNITURA_SHEET);
    sh.getRange(1,1,1,5).setValues([['artikul','kategoriya','nomi','ulchov','soni']]);
    sh.getRange(1,1,1,5).setFontWeight('bold');
  }
  return sh;
}

function jsonOut(data) {
  return ContentService
    .createTextOutput(JSON.stringify(data))
    .setMimeType(ContentService.MimeType.JSON);
}

// ══════════════════════════════════════════════════════════════
//  doGet
// ══════════════════════════════════════════════════════════════
function doGet(e) {
  if (!e || !e.parameter) {
    return jsonOut({ error: 'Web App orqali ishlatilishi kerak.' });
  }
  const p = e.parameter;
  if (p.barcode) return jsonOut(getModuleByBarcode(p.barcode));
  if (p.action === 'file' && p.id) return jsonOut(getTelegramFileUrl(p.id));
  if ((p.password || '') !== CONFIG.PASSWORD) return jsonOut({ error: 'Noto\'g\'ri parol' });
  switch (p.action) {
    case 'modules': return jsonOut(getAllModules());
    case 'ping':    return jsonOut({ ok: true, time: new Date().toISOString() });
    default:        return jsonOut({ error: 'Noma\'lum action' });
  }
}

// ══════════════════════════════════════════════════════════════
//  doPost
// ══════════════════════════════════════════════════════════════
function doPost(e) {
  try {
    if (!e || !e.postData || !e.postData.contents) {
      return jsonOut({ error: 'POST body bo\'sh' });
    }
    const body = JSON.parse(e.postData.contents);
    if ((body.password || '') !== CONFIG.PASSWORD) return jsonOut({ error: 'Noto\'g\'ri parol' });
    switch (body.action) {
      case 'save_module':   return jsonOut(saveModule(body.module));
      case 'delete_module': return jsonOut(deleteModule(body.artikul));
      case 'upload_file':   return jsonOut(uploadToTelegram(body));
      default:              return jsonOut({ error: 'Noma\'lum action: ' + body.action });
    }
  } catch (err) {
    return jsonOut({ error: 'Server xatosi: ' + err.message });
  }
}

// ══════════════════════════════════════════════════════════════
//  BARCODE SEARCH
// ══════════════════════════════════════════════════════════════
function getModuleByBarcode(rawBarcode) {
  try {
    const barcode = rawBarcode.toString().trim().toUpperCase();
    const modSh   = getModullarSheet();
    const furSh   = getFurnituraSheet();
    const modData = modSh.getDataRange().getValues();
    const furData = furSh.getDataRange().getValues();

    let foundRow = null, foundArtikul = '';
    for (let i = 1; i < modData.length; i++) {
      const art = modData[i][M.ARTIKUL].toString().trim().toUpperCase();
      if (art && barcode.includes(art)) { foundRow = modData[i]; foundArtikul = art; break; }
    }
    if (!foundRow) return { error: 'Modul topilmadi: [' + barcode + ']' };

    const furnituralar = {};
    for (let i = 1; i < furData.length; i++) {
      const rowArt  = furData[i][F.ARTIKUL].toString().trim().toUpperCase();
      const furNomi = (furData[i][F.NOMI] || '').toString().trim();
      if (rowArt === foundArtikul && furNomi) {
        const kat = (furData[i][F.KAT] || 'Boshqa').toString().trim();
        if (!furnituralar[kat]) furnituralar[kat] = [];
        furnituralar[kat].push({
          nomi: furNomi,
          ulchov: (furData[i][F.ULCHOV] || '').toString(),
          soni:   (furData[i][F.SONI]   || '').toString(),
        });
      }
    }

    return {
      artikul:   foundRow[M.ARTIKUL].toString(),
      nomi:      foundRow[M.NOMI].toString(),
      tgPdfId:   foundRow[M.TG_PDF].toString(),
      tgVideoId: foundRow[M.TG_VIDEO].toString(),
      pdfUrl:    foundRow[M.PDF_URL].toString(),
      videoUrl:  foundRow[M.VIDEO_URL].toString(),
      furnituralar, error: '',
    };
  } catch (err) { return { error: 'Qidirish xatosi: ' + err.message }; }
}

// ══════════════════════════════════════════════════════════════
//  ADMIN — barcha modullar
// ══════════════════════════════════════════════════════════════
function getAllModules() {
  try {
    const modSh   = getModullarSheet();
    const furSh   = getFurnituraSheet();
    const modData = modSh.getDataRange().getValues();
    const furData = furSh.getDataRange().getValues();
    if (modData.length <= 1) return [];

    const furMap = {};
    for (let i = 1; i < furData.length; i++) {
      const art  = furData[i][F.ARTIKUL].toString().trim().toUpperCase();
      const nomi = (furData[i][F.NOMI] || '').toString().trim();
      if (!art || !nomi) continue;
      const kat = (furData[i][F.KAT] || 'Boshqa').toString().trim();
      if (!furMap[art]) furMap[art] = {};
      if (!furMap[art][kat]) furMap[art][kat] = [];
      furMap[art][kat].push({ nomi, ulchov: (furData[i][F.ULCHOV]||'').toString(), soni: (furData[i][F.SONI]||'').toString() });
    }

    return modData.slice(1).map(row => {
      const artikul = row[M.ARTIKUL].toString().trim();
      if (!artikul) return null;
      return {
        artikul,
        nomi:        row[M.NOMI].toString(),
        tgPdfId:     row[M.TG_PDF].toString(),
        tgVideoId:   row[M.TG_VIDEO].toString(),
        pdfUrl:      row[M.PDF_URL].toString(),
        videoUrl:    row[M.VIDEO_URL].toString(),
        furnituralar: furMap[artikul.toUpperCase()] || {},
        error: '',
      };
    }).filter(Boolean);
  } catch (err) { return { error: err.message }; }
}

// ══════════════════════════════════════════════════════════════
//  ADMIN — saqlash
// ══════════════════════════════════════════════════════════════
function saveModule(module) {
  try {
    if (!module || !module.artikul) return { error: 'Artikul bo\'sh' };
    const artikul = module.artikul.trim();
    const artUp   = artikul.toUpperCase();
    const modSh   = getModullarSheet();
    const furSh   = getFurnituraSheet();

    const modData = modSh.getDataRange().getValues();
    let modRow = -1;
    for (let i = 1; i < modData.length; i++) {
      if (modData[i][M.ARTIKUL].toString().trim().toUpperCase() === artUp) { modRow = i + 1; break; }
    }
    const rowData = [artikul, module.nomi||'', module.tgPdfId||'', module.tgVideoId||'', module.pdfUrl||'', module.videoUrl||''];
    if (modRow > 0) { modSh.getRange(modRow, 1, 1, 6).setValues([rowData]); }
    else { modSh.appendRow(rowData); }

    const furData = furSh.getDataRange().getValues();
    for (let i = furData.length - 1; i >= 1; i--) {
      if (furData[i][F.ARTIKUL].toString().trim().toUpperCase() === artUp) furSh.deleteRow(i + 1);
    }
    Object.entries(module.furnituralar || {}).forEach(([kat, items]) => {
      (items || []).forEach(item => {
        if (item.nomi && item.nomi.trim()) furSh.appendRow([artikul, kat, item.nomi||'', item.ulchov||'', item.soni||'']);
      });
    });

    return { ok: true, artikul };
  } catch (err) { return { error: err.message }; }
}

// ══════════════════════════════════════════════════════════════
//  ADMIN — o'chirish
// ══════════════════════════════════════════════════════════════
function deleteModule(artikul) {
  try {
    if (!artikul) return { error: 'Artikul kiritilmagan' };
    const artUp = artikul.toString().trim().toUpperCase();
    const modSh = getModullarSheet(), furSh = getFurnituraSheet();
    const modData = modSh.getDataRange().getValues();
    for (let i = modData.length - 1; i >= 1; i--) {
      if (modData[i][M.ARTIKUL].toString().trim().toUpperCase() === artUp) modSh.deleteRow(i + 1);
    }
    const furData = furSh.getDataRange().getValues();
    for (let i = furData.length - 1; i >= 1; i--) {
      if (furData[i][F.ARTIKUL].toString().trim().toUpperCase() === artUp) furSh.deleteRow(i + 1);
    }
    return { ok: true };
  } catch (err) { return { error: err.message }; }
}

// ══════════════════════════════════════════════════════════════
//  TELEGRAM — file_id → URL
// ══════════════════════════════════════════════════════════════
function getTelegramFileUrl(fileId) {
  try {
    const res  = UrlFetchApp.fetch(
      `https://api.telegram.org/bot${CONFIG.BOT_TOKEN}/getFile?file_id=${fileId}`,
      { muteHttpExceptions: true }
    );
    const data = JSON.parse(res.getContentText());
    if (!data.ok) return { error: data.description || 'getFile xatosi' };
    return { url: `https://api.telegram.org/file/bot${CONFIG.BOT_TOKEN}/${data.result.file_path}` };
  } catch (err) { return { error: err.message }; }
}

// ══════════════════════════════════════════════════════════════
//  TELEGRAM — fayl yuklash
//
//  MUHIM: fileType = 'pdf' yoki 'video' — admin paneldan keladi
//  Bu orqali PDF va Video file_id larini aniq ajratamiz
// ══════════════════════════════════════════════════════════════
function uploadToTelegram(body) {
  try {
    const { fileBase64, fileName, mimeType, fileType } = body;
    if (!fileBase64 || !fileName) return { error: 'fileBase64 yoki fileName yo\'q' };

    // fileType eng ishonchli usul: 'pdf' yoki 'video'
    // mimeType va fileName faqat zaxira sifatida
    const isPdf   = fileType === 'pdf' ||
                    (mimeType || '').includes('pdf') ||
                    /\.pdf$/i.test(fileName);

    const isVideo = !isPdf && (
                    fileType === 'video' ||
                    (mimeType || '').includes('video') ||
                    /\.(mp4|mov|avi|mkv|webm|m4v)$/i.test(fileName)
                    );

    const bytes = Utilities.base64Decode(fileBase64);
    const blob  = Utilities.newBlob(bytes, mimeType || 'application/octet-stream', fileName);

    Logger.log('uploadToTelegram: fileType=' + fileType + ' isPdf=' + isPdf + ' isVideo=' + isVideo + ' fileName=' + fileName);

    let fileId = '';

    if (isPdf) {
      // ── PDF → sendDocument ────────────────────────────
      const res  = UrlFetchApp.fetch(
        `https://api.telegram.org/bot${CONFIG.BOT_TOKEN}/sendDocument`,
        { method: 'post', payload: { chat_id: CONFIG.CHAT_ID, document: blob }, muteHttpExceptions: true }
      );
      const data = JSON.parse(res.getContentText());
      Logger.log('sendDocument result: ' + JSON.stringify(data).slice(0, 300));
      if (!data.ok) return { error: 'PDF yuklashda xato: ' + (data.description || 'noma\'lum') };
      fileId = data.result.document?.file_id || '';

    } else if (isVideo) {
      // ── Video → sendVideo (birinchi urinish) ──────────
      const res  = UrlFetchApp.fetch(
        `https://api.telegram.org/bot${CONFIG.BOT_TOKEN}/sendVideo`,
        { method: 'post', payload: { chat_id: CONFIG.CHAT_ID, video: blob }, muteHttpExceptions: true }
      );
      const data = JSON.parse(res.getContentText());
      Logger.log('sendVideo result: ' + JSON.stringify(data).slice(0, 300));

      if (data.ok) {
        // video, document, animation — barchasini tekshiramiz
        fileId = data.result.video?.file_id
              || data.result.document?.file_id
              || data.result.animation?.file_id
              || '';
      } else {
        // sendVideo muvaffaqiyatsiz → sendDocument bilan qayta urinish
        Logger.log('sendVideo xato, sendDocument bilan qayta urinilmoqda...');
        const res2  = UrlFetchApp.fetch(
          `https://api.telegram.org/bot${CONFIG.BOT_TOKEN}/sendDocument`,
          { method: 'post', payload: { chat_id: CONFIG.CHAT_ID, document: blob }, muteHttpExceptions: true }
        );
        const data2 = JSON.parse(res2.getContentText());
        Logger.log('sendDocument (fallback) result: ' + JSON.stringify(data2).slice(0, 300));
        if (!data2.ok) return { error: 'Video yuklashda xato: ' + (data2.description || 'noma\'lum') };
        fileId = data2.result.document?.file_id || data2.result.video?.file_id || '';
      }

    } else {
      // Tur aniqlanmadi — sendDocument
      const res  = UrlFetchApp.fetch(
        `https://api.telegram.org/bot${CONFIG.BOT_TOKEN}/sendDocument`,
        { method: 'post', payload: { chat_id: CONFIG.CHAT_ID, document: blob }, muteHttpExceptions: true }
      );
      const data = JSON.parse(res.getContentText());
      if (!data.ok) return { error: 'Yuklashda xato: ' + (data.description || 'noma\'lum') };
      fileId = data.result.document?.file_id || '';
    }

    if (!fileId) {
      return { error: 'file_id topilmadi! fileType=' + fileType + ' fileName=' + fileName };
    }

    Logger.log('Yuklandi! fileType=' + fileType + ' file_id=' + fileId);
    return { ok: true, file_id: fileId };

  } catch (err) {
    return { error: err.message };
  }
}

// ══════════════════════════════════════════════════════════════
//  TEST
// ══════════════════════════════════════════════════════════════
function testScript() {
  Logger.log('=== TEST BOSHLANDI ===');
  try { getModullarSheet(); getFurnituraSheet(); Logger.log('✅ Varaqlar OK'); }
  catch(e) { Logger.log('❌ Sheet: ' + e.message); }

  if (CONFIG.BOT_TOKEN !== 'YOUR_BOT_TOKEN') {
    try {
      const r = UrlFetchApp.fetch(`https://api.telegram.org/bot${CONFIG.BOT_TOKEN}/getMe`);
      Logger.log('✅ Telegram: @' + JSON.parse(r.getContentText()).result.username);
    } catch(e) { Logger.log('❌ Telegram: ' + e.message); }
  } else {
    Logger.log('⚠️ BOT_TOKEN sozlanmagan');
  }

  const mods = getAllModules();
  Logger.log('📦 Modullar: ' + (Array.isArray(mods) ? mods.length + ' ta' : JSON.stringify(mods)));
  Logger.log('=== TEST TUGADI ===');
}
