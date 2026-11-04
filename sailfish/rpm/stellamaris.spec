Name:       stellamaris
Summary:    Status and remote control of a PSA/Stellantis car, on psa_car_controller
Version:    0.3.0
Release:    2
License:    GPLv3+
URL:        https://github.com/flobz/psa_car_controller
Source0:    %{name}-%{version}.tar.bz2
Requires:   sailfishsilica-qt5 >= 0.10.9
Requires:   libsailfishapp-launcher
Requires:   pyotherside-qml-plugin-python3-qt5 >= 1.5
Requires:   python3-base
# The app was called psacar before; installing stellamaris replaces it.
Obsoletes:  psacar < 0.2

# lib/ holds the bundled Python packages, private to the app: no automatic provides or requires from them.
%define __provides_exclude_from ^%{_datadir}/%{name}/.*$
%define __requires_exclude_from ^%{_datadir}/%{name}/.*$
# The native modules in lib/ come prebuilt from PyPI wheels; there is no debug info to extract.
%global debug_package %{nil}

%description
Shows the status of a PSA/Stellantis car and sends commands (preconditioning, charging, wake-up).
Uses an unmodified psa_car_controller release, bundled in /usr/share/%{name}/lib.
Run tools/prepare-sailfish.sh before building.

%prep
%setup -q -n %{name}-%{version}

%build

%install
mkdir -p %{buildroot}%{_datadir}/%{name}
cp -r qml python lib %{buildroot}%{_datadir}/%{name}/
install -D -m 644 %{name}.desktop %{buildroot}%{_datadir}/applications/%{name}.desktop
for size in 86x86 108x108 128x128 172x172; do
    install -D -m 644 icons/$size/%{name}.png %{buildroot}%{_datadir}/icons/hicolor/$size/apps/%{name}.png
done

%files
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png
