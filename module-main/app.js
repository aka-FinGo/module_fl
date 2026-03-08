const API_URL = "https://script.google.com/macros/s/AKfycbxyWSaRdn-4NZkkwJiAb2Q-uezsE8U_iFhjdSfsd4vZRHodaQ-aLhMNZe9ZwqjdVMjQ/exec"; 
const html5QrCode = new Html5Qrcode("reader");
const viewportMeta = document.querySelector('meta[name="viewport"]');

let currentData = null;
let torchOn = false;

function playSuccessBeep() {
    try {
        if (navigator.vibrate) navigator.vibrate(200);
        const ctx = new (window.AudioContext || window.webkitAudioContext)();
        const osc = ctx.createOscillator();
        const gainNode = ctx.createGain();
        osc.connect(gainNode);
        gainNode.connect(ctx.destination);
        osc.type = 'sine';
        osc.frequency.setValueAtTime(880, ctx.currentTime);
        gainNode.gain.setValueAtTime(0.1, ctx.currentTime);
        osc.start();
        osc.stop(ctx.currentTime + 0.15);
    } catch (e) { console.log("Audio xatosi", e); }
}

function saveToHistory(data) {
    let history = JSON.parse(localStorage.getItem('scanHistory') || '[]');
    history = history.filter(item => item.artikul !== data.artikul);
    history.unshift(data);
    if (history.length > 10) history.pop();
    localStorage.setItem('scanHistory', JSON.stringify(history));
    loadHistory();
}

function loadHistory() {
    const list = document.getElementById('history-list');
    let history = JSON.parse(localStorage.getItem('scanHistory') || '[]');
    if (history.length === 0) {
        list.innerHTML = "<p style='color:#7f8c8d; font-size: 14px;'>Hozircha tarix yo'q.</p>";
        return;
    }
    list.innerHTML = history.map(item => {
        let imgTag = '<div class="history-img" style="display:flex;align-items:center;justify-content:center;font-size:10px;">PDF yo\'q</div>';
        if (item.pdfUrl) {
            let match = item.pdfUrl.match(/[-\w]{25,}/);
            if (match) imgTag = `<img src="https://drive.google.com/thumbnail?id=${match[0]}&sz=w100-h100" class="history-img" alt="PDF">`;
        }
        return `
        <div class="history-item" onclick="loadFromHistory('${item.artikul}')">
            ${imgTag}
            <div style="flex-grow:1;">
                <strong>${item.artikul}</strong><br>
                <span style="font-size:12px; color:#27ae60; font-weight:bold;">${item.nomi || 'Nomi kiritilmagan'}</span>
            </div>
            <span style="color:#7f8c8d; font-size:20px;">➔</span>
        </div>`;
    }).join('');
}

function loadFromHistory(artikul) {
    let history = JSON.parse(localStorage.getItem('scanHistory') || '[]');
    let data = history.find(i => i.artikul === artikul);
    if (data) {
        currentData = data;
        enableNavs();
        renderFurnitura();
    }
}

window.onload = loadHistory;

function showPage(pageId) {
    document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
    document.getElementById(`page-${pageId}`).classList.add('active');
    document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
    
    if (pageId === 'home') {
        document.getElementById('nav-home').classList.add('active');
        document.getElementById('app-title').textContent = "Aristokrat Mebel";
    }
}

function enableNavs() {
    document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('disabled'));
    document.getElementById('app-title').textContent = `Artikul: ${currentData.artikul}`;
}
function startScan() {
    showPage('scanner');
    document.getElementById('app-title').textContent = "Skanerlash...";
    
    html5QrCode.start(
        { facingMode: "environment" }, 
        { 
            fps: 15, 
            qrbox: { width: 250, height: 250 },
            useBarCodeDetectorIfSupported: true,
            formatsToSupport: [
                Html5QrcodeSupportedFormats.QR_CODE,
                Html5QrcodeSupportedFormats.CODE_128,
                Html5QrcodeSupportedFormats.CODE_39,
                Html5QrcodeSupportedFormats.EAN_13,
                Html5QrcodeSupportedFormats.EAN_8
            ]
        }, 
        onScanSuccess
    ).then(() => {
        document.getElementById('btn-torch').addEventListener('click', toggleTorch);
    }).catch(err => alert("Kamera topilmadi yoki ruxsat yo'q!"));
}

function toggleTorch() {
    torchOn = !torchOn;
    html5QrCode.applyVideoConstraints({ advanced: [{ torch: torchOn }] });
    document.getElementById('btn-torch').style.background = torchOn ? "#f1c40f" : "#2980b9";
}

function stopScanner() {
    html5QrCode.stop().then(() => { torchOn = false; showPage('home'); }).catch(() => { showPage('home'); });
}

function onScanSuccess(decodedText) {
    playSuccessBeep();
    html5QrCode.stop().then(() => { torchOn = false; fetchData(decodedText); }).catch(() => { fetchData(decodedText); });
}

function fetchData(barcode) {
    showPage('content');
    document.getElementById('dynamic-content').innerHTML = "";
    document.getElementById('skeleton-loader').classList.remove('hidden');
    document.getElementById('app-title').textContent = `Qidirish: [${barcode}]`;
    
    fetch(`${API_URL}?barcode=${encodeURIComponent(barcode)}`)
        .then(res => res.json())
        .then(data => {
            document.getElementById('skeleton-loader').classList.add('hidden');
            if (data.error) {
                document.getElementById('dynamic-content').innerHTML = `<h3 style="color:red; text-align:center; padding:20px;">${data.error}</h3>`;
                return;
            }
            currentData = data;
            saveToHistory(data);
            enableNavs();
            renderFurnitura();
        }).catch(err => {
            document.getElementById('skeleton-loader').classList.add('hidden');
            let errorMsg = "Tarmoq xatosi yoki CORS! Google Sheets 'Deploy' sozlamalarini tekshiring.";
            if (!navigator.onLine) errorMsg = "Internetga ulanish yo'q!";
            
            document.getElementById('dynamic-content').innerHTML = `
                <div style="padding: 20px; text-align: center;">
                    <h3 style="color:red;">${errorMsg}</h3>
                    <p style="font-size: 12px; color: #7f8c8d; margin-top: 10px;">Texnik xato: ${err.message}</p>
                </div>
            `;
        });
}

function updateNavStyle(type) {
    showPage('content');
    document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
    document.getElementById(`nav-${type === 'furnitura' ? 'fur' : type === 'pdf' ? 'pdf' : 'vid'}`).classList.add('active');
}
window.renderFurnitura = function() {
    if (!currentData) return;
    updateNavStyle('furnitura');
    let html = "";
    let furs = currentData.furnituralar;
    
    if (!furs || Object.keys(furs).length === 0) {
        html = "<p style='text-align:center; padding: 20px;'>Bu modul uchun furnitura yo'q.</p>";
    } else {
        for (let category in furs) {
            if (!furs[category] || furs[category].length === 0) continue;

            // Barchasi yopiq (▶) va open klassisiz boshlanadi
            html += `<div class="accordion-header" onclick="toggleAccordion(this)">${category} <span class="acc-icon">▶</span></div>`;
            html += `<div class="accordion-body">`; 
            
            furs[category].forEach((item, index) => {
                let uid = `${currentData.artikul}_${category.replace(/[^a-zA-Z0-9]/g, '')}_${index}`;
                let isChecked = localStorage.getItem(uid) === 'true';
                let checkClass = isChecked ? 'checked' : '';
                
                html += `
                <div class="fur-item ${checkClass}" id="${uid}" onclick="toggleCheck('${uid}')">
                    <div class="fur-details">
                        <span class="fur-name">${item.nomi}</span>
                        <span class="fur-size">${item.ulchov}</span>
                    </div>
                    <strong>${item.soni}</strong>
                </div>`;
            });
            html += `</div>`;
        }
        // Pastda qolib ketmasligi uchun jismoniy bufer (Spacer)
        html += `<div style="height: 150px; width: 100%; pointer-events: none;"></div>`;
    }
    document.getElementById('dynamic-content').innerHTML = html;
    sortCheckedItems();
};

window.toggleAccordion = function(el) {
    let body = el.nextElementSibling;
    let icon = el.querySelector('.acc-icon');
    let isOpen = body.classList.contains('open');

    // Avval hamma Accordion larni yopish (Exclusive mantig'i)
    document.querySelectorAll('.accordion-body').forEach(b => b.classList.remove('open'));
    document.querySelectorAll('.acc-icon').forEach(i => i.textContent = '▶');

    // Agar hozir bosilgan guruh yopiq bo'lgan bo'lsa, uni ochish
    if (!isOpen) {
        body.classList.add('open');
        icon.textContent = '▼';
    }
};

window.toggleCheck = function(uid) {
    let el = document.getElementById(uid);
    let isChecked = el.classList.toggle('checked');
    localStorage.setItem(uid, isChecked);
    sortCheckedItems();
};

window.sortCheckedItems = function() {
    document.querySelectorAll('.accordion-body').forEach(body => {
        let items = Array.from(body.querySelectorAll('.fur-item'));
        items.sort((a, b) => {
            let aChk = a.classList.contains('checked') ? 1 : 0;
            let bChk = b.classList.contains('checked') ? 1 : 0;
            return aChk - bChk;
        });
        items.forEach(item => body.appendChild(item));
    });
};
window.renderIframe = function(type) {
    if (!currentData) return;
    updateNavStyle(type);
    
    let url = type === 'pdf' ? currentData.pdfUrl : currentData.videoUrl;
    if (!url) {
        document.getElementById('dynamic-content').innerHTML = `<p style='text-align:center; padding: 20px;'>Bu qism kiritilmagan.</p>`;
        return;
    }

    let finalUrl = url;
    if (type === "video") {
        let vidId = "";
        if (url.includes("youtu.be/")) vidId = url.split("youtu.be/")[1].split("?")[0];
        else if (url.includes("youtube.com/watch")) vidId = new URL(url).searchParams.get("v");
        finalUrl = `https://www.youtube.com/embed/${vidId}?modestbranding=1&rel=0&controls=1`;
    } else if (type === "pdf") {
        let fileIdMatch = url.match(/[-\w]{25,}/);
        if (fileIdMatch) {
            finalUrl = `https://docs.google.com/viewer?url=${encodeURIComponent('https://drive.google.com/uc?export=download&id=' + fileIdMatch[0])}&embedded=true`;
        }
    }

    document.getElementById('dynamic-content').innerHTML = `
        <div style="display:flex; justify-content:flex-end; margin-bottom:10px;">
            <button class="btn btn-primary" style="padding:10px; font-size:14px; background:#27ae60;" onclick="openNativeFullscreen('${finalUrl}', '${type}')">⛶ To'liq ekran</button>
        </div>
        <div class="iframe-wrapper">
            <div class="anti-leak-shield"></div>
            <iframe src="${finalUrl}" class="secure-iframe" allow="autoplay; encrypted-media; fullscreen" allowfullscreen></iframe>
        </div>
    `;
};

window.openNativeFullscreen = function(url, type) {
    if (viewportMeta) viewportMeta.setAttribute("content", "width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes");
    document.getElementById("modal-title-text").textContent = type === "pdf" ? "Chizma" : "Video";
    document.getElementById("anti-leak-shield").classList.remove("hidden");
    document.getElementById("iframe-container").innerHTML = `<iframe src="${url}" class="secure-iframe" allow="autoplay; encrypted-media; fullscreen" allowfullscreen></iframe>`;
    document.getElementById("fullscreen-modal").classList.remove("hidden");
};

window.closeNativeFullscreen = function() {
    if (viewportMeta) viewportMeta.setAttribute("content", "width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover");
    document.getElementById("iframe-container").innerHTML = "";
    document.getElementById("fullscreen-modal").classList.add("hidden");
};
