// SPDX-License-Identifier: MIT-0

'use strict';

const xmlPath = 'xml';

const iframeMargin = 50;

const category_names =
    { base: "Base", simdfp: "SIMD&FP", sve: "SVE", sme: "SME" };
const category_ids =
    { "Base": "base", "SIMD&FP": "simdfp", "SVE": "sve", "SME": "sme" };

const instrForm = document.getElementById("instr-form");
const instrList = document.getElementById("instr-list");
const instrInput = document.getElementById("instr-input");
const instrIframe = document.getElementById("instr-iframe");
const showButton = document.getElementById("instr-show");
const openButton = document.getElementById("instr-open");

function createInstrList() {
    for (let instr of instrs) {
        let category = category_names[instr.category];
        let option = document.createElement("option");
        option.value = `${instr.mnemonic} (${category}) [${instr.heading}]`;
        option.label = `${option.value} - ${instr.brief}`;
        option.category = instr.category;
        option.mnemonic = instr.mnemonic;
        instrList.appendChild(option);
    }
}

function changeInstrList() {
    let input = instrInput.value.toUpperCase();
    let categories = {
        base: document.getElementById("instr-base").checked,
        simdfp: document.getElementById("instr-simdfp").checked,
        sve: document.getElementById("instr-sve").checked,
        sme: document.getElementById("instr-sme").checked
    };

    if (input.includes(' ')) {
        let mnemonic = input.replace(/ .*/, '');
        for (let option of instrList.childNodes) {
            option.disabled = ! (option.mnemonic == mnemonic &&
                                 categories[option.category]);
        }
    } else {
        for (let option of instrList.childNodes) {
            option.disabled = ! (option.mnemonic.startsWith(input) &&
                                 categories[option.category]);
        }
    }
}

function findInstr() {
    const regexp = /^(\w+) \(([\w&]+)\) \[(.+)\]$/;
    let match = instrInput.value.match(regexp);
    if (! match) {
        return;
    }
    let mnemonic = match[1];
    let category = category_ids[match[2]];
    let heading = match[3];

    return instrs.find(instr =>
        instr.mnemonic == mnemonic &&
        instr.category == category &&
        instr.heading == heading);
}

function showInIframe() {
    let instr = findInstr();
    if (instr) {
        instrIframe.src = xmlPath + '/xhtml/' + instr.file;
    }
}

function openInWindow() {
    let instr = findInstr();
    if (instr) {
        window.open(xmlPath + '/xhtml/' + instr.file);
    }
}

function adjustIframeHeight() {
    instrIframe.height =
        (instrIframe.src && instrIframe.contentDocument) ?
        (instrIframe.contentDocument.body.scrollHeight + iframeMargin) :
        (window.innerHeight - instrForm.clientHeight - iframeMargin);
}

createInstrList();
adjustIframeHeight();
window.addEventListener('resize', adjustIframeHeight);
instrIframe.addEventListener('load', adjustIframeHeight);
instrInput.addEventListener('input', changeInstrList);
showButton.addEventListener('click', showInIframe);
openButton.addEventListener('click', openInWindow);
instrForm.addEventListener(
    'submit', (event) => { showInIframe(); event.preventDefault(); });
