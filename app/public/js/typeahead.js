// typeahead.js - the suggestion list under a lookup box (CBGPSuggest.attach).
//
// Why this exists instead of an HTML <datalist>:
//  * a datalist makes the BROWSER filter the options again, by the text typed,
//    literally. The server ignores accents, so typing "Alarco" found
//    "Alarcón Moreno" - and the browser then hid it again, because "Alarco" is
//    not literally inside "Alarcón".
//  * a datalist can only hand back the text of the chosen row, so two people
//    with the same label could not be told apart: the page kept one of them.
// This list shows exactly what the server returned, and hands back the chosen
// ITEM ({value, label}) itself.
//
//   CBGPSuggest.attach(inputElement, {
//     fetchItems: function (query) { return Promise.resolve([{ value: 'x', label: 'X' }]); },
//     onPick:     function (item)  { ... },
//     minLength: 2,      // characters before searching (default 2)
//     delay: 250         // ms to wait after the last key (default 250; 0 = no wait)
//   });
(function (global) {
  'use strict';

  var uid = 0;

  function attach(input, options) {
    var minLength = options.minLength === undefined ? 2 : options.minLength;
    var delay = options.delay === undefined ? 250 : options.delay;
    var list = null;      // the <ul>, only while open
    var items = [];       // what the open list shows
    var active = -1;      // highlighted row
    var timer = null;
    var seq = 0;          // answers to older keystrokes are ignored
    var listId = 'cbgp-suggest-' + (++uid);

    input.setAttribute('autocomplete', 'off');
    input.setAttribute('role', 'combobox');
    input.setAttribute('aria-autocomplete', 'list');
    input.setAttribute('aria-expanded', 'false');

    function close() {
      if (list && list.parentNode) { list.parentNode.removeChild(list); }
      list = null;
      items = [];
      active = -1;
      input.setAttribute('aria-expanded', 'false');
      input.removeAttribute('aria-activedescendant');
    }

    function highlight(index) {
      if (!list) { return; }
      var rows = list.children;
      for (var i = 0; i < rows.length; i++) { rows[i].classList.toggle('active', i === index); }
      active = index;
      if (index >= 0) {
        input.setAttribute('aria-activedescendant', rows[index].id);
        rows[index].scrollIntoView({ block: 'nearest' });
      } else {
        input.removeAttribute('aria-activedescendant');
      }
    }

    function pick(index) {
      var item = items[index];
      close();
      if (item) { options.onPick(item); }
    }

    function render(found) {
      close();
      if (!found || !found.length) { return; }
      items = found;
      list = document.createElement('ul');
      list.id = listId;
      list.className = 'cbgp-suggest';
      list.setAttribute('role', 'listbox');

      // Two choices that read the same get their stored value shown too.
      var seen = {};
      found.forEach(function (item) { seen[item.label] = (seen[item.label] || 0) + 1; });

      found.forEach(function (item, i) {
        var row = document.createElement('li');
        row.id = listId + '-' + i;
        row.setAttribute('role', 'option');
        row.appendChild(document.createTextNode(item.label));
        if (seen[item.label] > 1 && item.value !== item.label) {
          var key = document.createElement('span');
          key.className = 'cbgp-suggest-key';
          key.textContent = item.value;
          row.appendChild(key);
        }
        // mousedown, not click: it fires before the input loses focus (blur closes the list)
        row.addEventListener('mousedown', function (event) { event.preventDefault(); pick(i); });
        row.addEventListener('mousemove', function () { if (active !== i) { highlight(i); } });
        list.appendChild(row);
      });

      var box = input.getBoundingClientRect();
      list.style.left = (box.left + window.pageXOffset) + 'px';
      list.style.top = (box.bottom + window.pageYOffset) + 'px';
      list.style.minWidth = box.width + 'px';
      document.body.appendChild(list);
      input.setAttribute('aria-expanded', 'true');
      input.setAttribute('aria-controls', listId);
    }

    function search(query) {
      var mine = ++seq;
      options.fetchItems(query).then(function (found) {
        if (mine === seq) { render(found); }
      }).catch(function (err) { console.error('[typeahead] lookup failed:', err); });
    }

    input.addEventListener('input', function () {
      var query = input.value.trim();
      clearTimeout(timer);
      seq++;                                   // anything still in flight is now stale
      if (query.length < minLength) { close(); return; }
      if (delay === 0) { search(query); } else { timer = setTimeout(function () { search(query); }, delay); }
    });

    input.addEventListener('keydown', function (event) {
      if (event.key === 'ArrowDown' && items.length) {
        event.preventDefault();
        highlight(active < items.length - 1 ? active + 1 : 0);
      } else if (event.key === 'ArrowUp' && items.length) {
        event.preventDefault();
        highlight(active > 0 ? active - 1 : items.length - 1);
      } else if (event.key === 'Enter' && list && active >= 0) {
        event.preventDefault();                // choose the row, do not submit the form
        pick(active);
      } else if (event.key === 'Escape' || event.key === 'Tab') {
        close();
      }
    });

    input.addEventListener('blur', function () { setTimeout(close, 100); });
    window.addEventListener('resize', close);
  }

  global.CBGPSuggest = { attach: attach };
})(window);
