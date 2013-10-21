#!/local/python/bin/python2

from __future__ import print_function
from argparse import ArgumentParser
from datetime import datetime
import errno
import os
import os.path
import subprocess
import sys
import re
try:
    from Tkinter import *
    from tkFont import Font
    from tkMessageBox import showerror
except ImportError:
    from tkinter import *
    from tkinter.font import Font
    from tkinter.messagebox import showerror
import xml.etree.ElementTree as ET

bands = {
    'Band 1': 'band_1',
    'Band 2': 'band_2',
    'Band 3': 'band_3',
    'Band 4': 'band_4',
    'Band 5': 'band_5',
}

instruments = {
    'SCUBA-2': 'scuba-2',
    'HARP': 'harp',
    'RxA3': 'rxa3',
}

queries = {
    'JLS': 'jls',
    'PI projects': 'pi',
    'Nothing left': 'nl',
}

valid_date = re.compile('^\d\d\d\d-\d\d-\d\d$')
valid_time = re.compile('^\d\d-\d\d-\d\d$')

class ObserveBackup(Frame):
    def __init__(self):
        Frame.__init__(self, None)
        self.pack()

        label = Label(self, text='Date: ')
        label.grid(row=0, column=0)

        self.date = StringVar()
        self.date.set(dates[-1])
        date_menu = OptionMenu(self, self.date, *dates)
        date_menu.grid(row=0, column=1)

        label = Label(self, text='   Band: ')
        label.grid(row=0, column=2)

        self.band = StringVar()
        band_list = sorted(bands.keys())
        self.band.set(band_list[0])
        band_menu = OptionMenu(self, self.band, *band_list)
        band_menu.grid(row=0, column=3)

        label = Label(self, text='   Instrument: ')
        label.grid(row=0, column=4)

        self.instrument = StringVar()
        instrument_list = sorted(instruments.keys())
        self.instrument.set(instrument_list[-1])
        instrument_menu = OptionMenu(self, self.instrument, *instrument_list)
        instrument_menu.grid(row=0, column=5)

        label = Label(self, text='   Query type: ')
        label.grid(row=0, column=6)

        self.query = StringVar()
        query_list = sorted(queries.keys())
        self.query.set(query_list[0])
        query_menu = OptionMenu(self, self.query, *query_list)
        query_menu.grid(row=0, column=7)

        label = Label(self, text='    ')
        label.grid(row=0, column=8)

        search = Button(self, text='Search', command=self.search)
        search.grid(row=0, column=9)

        self.results = None

    def search(self):
        times = []
        for time in os.listdir(os.path.join(args.directory, self.date.get())):
            if valid_time.match(time):
                times.append(time)

        current_time = datetime.now().strftime('%H-%M-%S')

        if current_time in times:
            best_time = current_time
        else:
            times.append(current_time)
            times.sort()
            i = times.index(current_time)
            if i == len(times) - 1:
                best_time = times[0]
            else:
                best_time = times[i + 1]

        directory = os.path.join(
            args.directory,
            self.date.get(),
            best_time,
            bands[self.band.get()],
            instruments[self.instrument.get()],
            queries[self.query.get()])

        if self.results is not None:
            self.results.destroy()

        self.results = LabelFrame(self, text='Results')
        self.results.grid(row=1, column=0, columnspan=10)

        label = Label(self.results, text='Directory: ' + directory)
        label.pack()
        label = Label(self.results, text='Time: ' + best_time)
        label.pack()

        if not os.path.exists(directory):
            label = Label(self.results, text="No results")
            label.pack()
            return

        msbs = []

        for file in sorted(os.listdir(directory)):
            if not file.endswith('.xml'):
                continue

            xmlfile = str(os.path.join(directory, file))
            infofile = os.path.join(directory, file[:-4] + '.info')

            if os.path.exists(infofile):
                tree = ET.parse(infofile)
                coordstype = tree.find('coordstype').text
                ra = tree.find('ra').text
                dec = tree.find('dec').text
                az = tree.find('az').text
                airmass = tree.find('airmass').text
                obstype = tree.find('type').text
                time = tree.find('timeest').text
                remaining = tree.find('remaining').text
                msbid = tree.find('msbid').text
            else:
                coordstype = ra = dec = az = airmass = obstype = time = \
                    remaining = msbid = ''


            description = '{0:40} {1:10} {2:12} {3:12} Az:{4:10} ' \
                'Airmass:{5:12} {6:10} {7:10} ID:{9:10} ' \
                'Remaining:{8:3}'.format(
                file, coordstype, ra, dec, az, airmass, obstype,
                time, remaining, msbid)

            line = Frame(self.results)
            line.pack(side='top')

            label = Label(line, text=description, font=monospace)
            label.pack(side='left')

            button = Button(line, text='Send to queue',
                command=callback_maker(self, xmlfile))
            button.pack(side='left')

    def send_to_queue(self, xmlfile):
        showerror('Error sending to queue', 'Not implemented.')


# For some reason, if we try to make the closure inside the
# file loop then we get a bunch of callbacks that all call
# with the same file (the last one used)...
def callback_maker(obj, file):
    def func():
        obj.send_to_queue(file)

    return func

parser = ArgumentParser()

parser.add_argument('--directory', type=str, dest='directory', required=True)

args = parser.parse_args()


# Check that we have the required tools available:

try:
    subprocess.check_output(['jcmttranslator', '--version'], stderr=subprocess.STDOUT)
except OSError as err:
    if err.errno == errno.ENOENT:
        print('Could not find the JCMT translator', file=sys.stderr)
        print('Please source the JCMT setup scripts:', file=sys.stderr)
        print('    /jcmt_sw/etc/cshrc', file=sys.stderr)
        print('    /jcmt_sw/etc/login', file=sys.stderr)
        exit(1)
    else:
        print('Could not launch the JCMT translator', file=sys.stderr)
        print(str(err), file=sys.stderr)
        exit(1)
except subprocess.CalledProcessError as err:
    print('Error testing the JCMT translator', file=sys.stderr)
    print(err.output, file=sys.stderr)
    exit(1)

try:
    subprocess.check_output(['ditscmd', '-h'], stderr=subprocess.STDOUT)
except OSError as err:
    if err.errno == errno.ENOENT:
        print('Could not find ditscmd', file=sys.stderr)
        print('Please source the ITS setup scripts:', file=sys.stderr)
        print('    /jac_sw/itsroot/etc/cshrc', file=sys.stderr)
        print('    /jac_sw/itsroot/etc/login', file=sys.stderr)
        exit(1)
    else:
        print('Could not launch ditscmd', file=sys.stderr)
        print(str(err), file=sys.stderr)
        exit(1)
except subprocess.CalledProcessError as err:
    print('Error testing ditscmd', file=sys.stderr)
    print(err.output, file=sys.stderr)
    exit(1)


# Start the application:

dates = sorted(filter((lambda x: valid_date.match(x)), os.listdir(args.directory)))

app = ObserveBackup()
monospace = Font(family='DejaVu Sans Mono', size=8)
app.master.title('Backup MSB Selection Tool')
app.mainloop()
