/*

Name:
  omp.js  

Description:
  Javascript functions used by the OMP web pages.

Author:
  Kynan Delorey <k.delorey@jach.hawaii.edu>

Copyright:
  Copyright (C) 2004-2005 Particle Physics and Astronomy Research Council.
  All Rights Reserved.

License:
  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
  General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place,Suite 330, Boston, MA 02111-1307,
  USA

*/

// Toggle the display of rows of a particular system and status
// If given a single argument, that argument should be the system
// of the rows to be hidden.  If more than one argument is given,
// the first argument should be the ID of a tag containing an
// attribute called 'function' that is defined as either 'show' or
// 'hide'.  The remaining arguments should be the systems of the rows
// to be closed.
function toggle(systemID) {
  var current;  // The current function that the 'button' performs
  if (arguments[1]) {
    functionTag = document.getElementById(arguments[0]);
    current = functionTag.getAttribute('function');
    toggleFunction(functionTag.id);
  }
  for (i = 0; i < arguments.length; i++) {
    toggleStatusInfo("info" + arguments[i]);
    var body = document.getElementsByTagName("body").item(0);
    var tr = body.getElementsByTagName("tr");
    for (j = 0; j <= tr.length; j++) {
      if (tr[j] && arguments[i] == tr[j].id.substring(0,11)) {
        var row = tr[j];
        var img = document.getElementById("img" + arguments[i]);
        var rowflag;
        if (current == 'show') {
          rowflag = 1;
        } else if (current == 'hide') {
          rowflag = 0;
        } else {
          // Just do inverse
	  rowflag = (row.className == 'hide');
        }
        row.className = (rowflag) ? 'show' : 'hide';
        img.src = (rowflag) ? 'http://omp.jach.hawaii.edu/images/hide.gif' : 'http://omp.jach.hawaii.edu/images/show.gif';
      }
    }
  }
}

function toggleFunction(ID) {
  var functionTag = document.getElementById(ID);
  var img = document.getElementById("img" + ID);
  var current = (functionTag.getAttribute('function') == 'hide') ? 'show' : 'hide';
  if (current == 'hide') {
    functionTag.innerHTML = 'Hide closed faults';
    functionTag.setAttribute('function', 'hide');
    img.src = 'http://omp.jach.hawaii.edu/images/hide.gif'
  } else {
    functionTag.innerHTML = 'Show closed faults';
    functionTag.setAttribute('function', 'show');
    img.src = 'http://omp.jach.hawaii.edu/images/show.gif'
  }
}

function toggleStatusInfo(ID) {
  var infoTag = document.getElementById(ID);
  if (infoTag) {
    if (! infoTag.innerHTML) {
      infoTag.innerHTML = infoTag.getAttribute('value');
    } else {
      infoTag.innerHTML = "";
    }
  }
}
