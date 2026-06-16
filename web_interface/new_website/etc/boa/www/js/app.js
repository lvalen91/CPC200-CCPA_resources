// Main Application Logic for CPC200-CCPA Web Interface

const App = {
    settings: {},
    boxInfo: {},
    deviceList: [],
    statsInterval: null,
    lastRx: 0,
    lastTx: 0,

    // Terminal state — cwd persists between commands (term.cgi is stateless,
    // so we echo the returned directory back on the next request).
    term: { cwd: '/', history: [], histIndex: 0, busy: false, acked: false },

    // Initialize application
    init: function() {
        console.log('[App] init called');
        this.setupTabs();
        this.setupToggles();
        this.setupRangeInputs();
        this.setupTerminal();
        console.log('[App] Setup complete, calling loadData');
        this.loadData();

        // Load full config dump and governor on startup
        this.loadFullConfig();
        this.loadGovernor();

        // Auto-start system stats refresh (every 2 seconds)
        this.updateStats();
        this.statsInterval = setInterval(() => this.updateStats(), 2000);
    },

    // Tab navigation
    setupTabs: function() {
        document.querySelectorAll('.tab').forEach(tab => {
            tab.addEventListener('click', () => {
                document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
                document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
                tab.classList.add('active');
                document.getElementById(tab.dataset.tab).classList.add('active');
            });
        });
    },

    // Toggle button groups
    setupToggles: function() {
        document.querySelectorAll('.toggle').forEach(toggle => {
            toggle.addEventListener('click', () => {
                var key = toggle.dataset.key;
                var val = toggle.dataset.value;
                this.setToggle(key, val, toggle);
            });
        });
    },

    // Range input handlers
    setupRangeInputs: function() {
        var naviVolume = document.getElementById('naviVolume');
        if (naviVolume) {
            naviVolume.addEventListener('input', function() {
                document.getElementById('naviVolumeValue').textContent = this.value;
            });
            naviVolume.addEventListener('change', function() {
                App.setSelect('naviVolume', this.value);
            });
        }
    },

    // Load all data from device
    loadData: function() {
        console.log('[App] loadData called');
        API.getInfos((err, data) => {
            console.log('[App] getInfos callback - err:', err, 'data:', data);
            if (err) {
                console.error('[App] Error loading data:', err);
                this.toast('Failed to load data', 'error');
                return;
            }
            if (data) {
                console.log('[App] Data received - Settings:', data.Settings);
                console.log('[App] Data received - BoxInfo:', data.BoxInfo);
                console.log('[App] Data received - DevList:', data.DevList);
                // API returns data directly (not wrapped in data.data)
                this.settings = data.Settings || {};
                this.boxInfo = data.BoxInfo || {};
                this.deviceList = data.DevList || [];
                this.wifiChannelList = data.WifiChannelList || [];

                // Fetch additional settings from riddle.conf that aren't in infos response
                this.loadExtendedConfig();
            } else {
                console.warn('[App] No data received');
            }
        });
    },

    // Load extended config settings not returned by infos API
    loadExtendedConfig: function() {
        fetch('/cgi-bin/config.cgi')
            .then(r => r.json())
            .then(config => {
                console.log('[App] Extended config loaded:', config);
                // Merge extended config into settings (config values take precedence for these keys)
                // Removed DEAD: UDiskPassThrough (zero runtime xrefs)
                // Removed PASS-THROUGH: ImprovedFluency, KnobMode, MouseMode (server.cgi only, no firmware effect)
                var extendedKeys = [
                    'MicType', 'BtAudio', 'BackgroundMode', 'HudGPSSwitch',
                    'FastConnect', 'AdvancedFeatures', 'CustomCarLogo', 'UdiskMode'
                ];
                extendedKeys.forEach(key => {
                    if (config[key] !== undefined) {
                        this.settings[key] = config[key];
                    }
                });
                console.log('[App] Merged settings:', this.settings);
                this.updateUI();
            })
            .catch(err => {
                console.warn('[App] Could not load extended config:', err);
                // Still update UI with what we have
                this.updateUI();
            });
    },

    // Update UI with loaded data
    updateUI: function() {
        // Update connection status
        this.updateConnectionStatus();

        // Update input fields from Settings
        this.setInputValue('mediaDelay', this.settings.mediaDelay);
        this.setInputValue('echoDelay', this.settings.echoDelay);
        this.setInputValue('ScreenDPI', this.settings.ScreenDPI);
        this.setInputValue('bitRate', this.settings.bitRate);
        this.setInputValue('startDelay', this.settings.startDelay);

        // These are in BoxInfo, not Settings
        this.setInputValue('wifiName', this.boxInfo.wifi || '');
        this.setInputValue('btName', this.boxInfo.bt || '');
        this.setInputValue('boxName', this.boxInfo.boxName || '');

        // Update range inputs
        if (this.settings.naviVolume !== undefined) {
            document.getElementById('naviVolume').value = this.settings.naviVolume;
            document.getElementById('naviVolumeValue').textContent = this.settings.naviVolume;
        }

        // Populate WiFi channel dropdown from adapter-reported supported channels
        if (this.wifiChannelList && this.wifiChannelList.length > 0) {
            this.populateWifiChannels(this.wifiChannelList);
        }

        // Update select inputs
        this.setSelectValue('wifiChannel', this.settings.wifiChannel);

        // Update toggle states
        this.updateToggles();

        // Update device list
        this.updateDeviceList();

        // Update info tab
        this.updateInfoTab();
    },

    setInputValue: function(id, value) {
        var el = document.getElementById(id);
        if (el && value !== undefined) el.value = value;
    },

    setSelectValue: function(id, value) {
        var el = document.getElementById(id);
        if (el && value !== undefined) el.value = value;
    },

    // Populate WiFi channel dropdown from adapter-reported channel list
    populateWifiChannels: function(channels) {
        var el = document.getElementById('wifiChannel');
        if (!el || !channels.length) return;
        // Only repopulate once (avoid flicker on refresh)
        if (el.dataset.populated) return;
        el.dataset.populated = '1';
        el.innerHTML = '';
        var group24 = document.createElement('optgroup');
        group24.label = '2.4 GHz';
        var group5 = document.createElement('optgroup');
        group5.label = '5 GHz';
        channels.forEach(function(ch) {
            var opt = document.createElement('option');
            // WifiChannelList entries are objects: {id: 36, wifiFreq: 5180}
            var chNum = (typeof ch === 'object' && ch !== null) ? ch.id : parseInt(ch);
            if (isNaN(chNum)) return;
            opt.value = chNum;
            opt.textContent = chNum;
            if (chNum <= 14) {
                group24.appendChild(opt);
            } else {
                group5.appendChild(opt);
            }
        });
        if (group24.children.length) el.appendChild(group24);
        if (group5.children.length) el.appendChild(group5);
    },

    // Update toggle button states based on settings
    updateToggles: function() {
        // Map HTML data-key to settings keys
        // infos API returns: mediaSound, autoConn, autoPlay (CallQuality removed — no effect on CarPlay)
        // config.cgi returns: MicType, BtAudio, BackgroundMode, HudGPSSwitch,
        //                     FastConnect, AdvancedFeatures, CustomCarLogo
        // Removed DEAD: UDiskPassThrough | Removed PASS-THROUGH: ImprovedFluency, KnobMode, MouseMode, DisplaySize
        var s = this.settings;
        var mappings = {
            'mediaSound': s.mediaSound,
            'micType': s.MicType,
            'BtAudio': s.BtAudio,
            'bgMode': s.BackgroundMode,
            'autoConn': s.autoConn,
            'autoPlay': s.autoPlay,
            'fastConnect': s.FastConnect,
            'gps': s.HudGPSSwitch,
            'UdiskMode': s.UdiskMode,
            'AdvancedFeatures': s.AdvancedFeatures,
            'CustomCarLogo': s.CustomCarLogo
        };

        console.log('[App] updateToggles - Settings keys:', Object.keys(this.settings));
        console.log('[App] updateToggles - Mapped values:', mappings);

        document.querySelectorAll('.toggle').forEach(toggle => {
            var key = toggle.dataset.key;
            var val = toggle.dataset.value;
            if (mappings[key] !== undefined && mappings[key].toString() === val) {
                toggle.classList.add('active');
            } else {
                toggle.classList.remove('active');
            }
        });

        // Show/hide logo upload based on customCarLogo
        var logoSection = document.getElementById('logoUploadSection');
        if (logoSection) {
            logoSection.style.display = this.settings.CustomCarLogo ? 'block' : 'none';
        }
    },

    // Update connection status display
    updateConnectionStatus: function() {
        var statusEl = document.getElementById('connectionStatus');
        var bigStatusEl = document.getElementById('bigStatus');
        var phoneInfoEl = document.getElementById('phoneInfo');
        var dot = statusEl.querySelector('.status-dot');
        var text = statusEl.querySelector('.status-text');

        var linkType = this.boxInfo.MDLinkType || '';
        var model = this.boxInfo.MDModel || '';

        // Find device name from deviceList matching the connection type
        var deviceName = '';
        if (linkType && this.deviceList && this.deviceList.length > 0) {
            var matchedDevice = this.deviceList.find(d => d.type === linkType);
            if (matchedDevice) {
                deviceName = matchedDevice.name || '';
            }
        }

        if (linkType) {
            dot.className = 'status-dot connected';
            text.textContent = linkType;
            bigStatusEl.textContent = linkType;
            bigStatusEl.className = 'big-status connected';
            // Show device name, model, and OS version
            var info = [];
            if (deviceName) info.push(deviceName);
            if (model) info.push(model);
            if (this.boxInfo.MDOSVersion) info.push('iOS ' + this.boxInfo.MDOSVersion);
            phoneInfoEl.textContent = info.join(' | ');
        } else {
            dot.className = 'status-dot';
            text.textContent = 'Disconnected';
            bigStatusEl.textContent = 'Disconnected';
            bigStatusEl.className = 'big-status';
            phoneInfoEl.textContent = '';
        }
    },

    // Update device list
    updateDeviceList: function() {
        var container = document.getElementById('deviceList');
        if (!this.deviceList || this.deviceList.length === 0) {
            container.innerHTML = '<p class="empty">No paired devices</p>';
            return;
        }

        var html = this.deviceList.map(device => {
            return '<div class="device-item">' +
                '<div class="device-info">' +
                '<span class="device-name">' + (device.name || device.id) + '</span>' +
                '<span class="device-type">' + (device.type || 'Unknown') + '</span>' +
                '</div>' +
                '<button class="btn btn-sm btn-danger" onclick="App.deleteDevice(\'' + device.id + '\')">Delete</button>' +
                '</div>';
        }).join('');

        container.innerHTML = html;
    },

    // Update info tab
    updateInfoTab: function() {
        document.getElementById('infoFirmware').textContent = this.boxInfo.ver || '--';
        document.getElementById('infoHardware').textContent = this.boxInfo.hardwareVer || '--';
        document.getElementById('infoSerial').textContent = this.boxInfo.uuid || '--';  // Use UUID as serial
        document.getElementById('infoUUID').textContent = this.boxInfo.uuid || '--';
        document.getElementById('infoProduct').textContent = this.boxInfo.productType || '--';
        document.getElementById('infoMfgDate').textContent = this.boxInfo.mfd || '--';
        document.getElementById('infoWifiChannel').textContent = this.settings.wifiChannel || '--';
        document.getElementById('infoBoxIP').textContent = window.location.hostname;
    },

    // Map HTML data-keys to server.cgi JSON field names
    // Most keys pass through directly — only list overrides where HTML key differs from API field
    // server.cgi accepts JSON field names (gps, bgMode, autoConn, autoPlay, etc.)
    // NOT config key names (HudGPSSwitch, BackgroundMode, NeedAutoConnect, etc.)
    keyMap: {
        // HTML data-key 'UdiskMode' → server.cgi UI field 'Udisk' (maps to UdiskMode config key internally)
        // server.cgi handles persistence (--upConfig) and side-effects; raw config.cgi -s does not.
        'UdiskMode': 'Udisk',
        // 'gps' → server.cgi field 'gps' (maps to HudGPSSwitch internally)
        // 'bgMode' → server.cgi field 'bgMode' (maps to BackgroundMode internally)
        // 'autoConn' → server.cgi field 'autoConn' (maps to NeedAutoConnect internally)
        // 'autoPlay' → server.cgi field 'autoPlay' (maps to AutoPlauMusic internally)
        // CallQuality removed — firmware bug + no effect on CarPlay audio (iPhone controls format via AirPlay)
    },

    // Keys not in server.cgi's 48-field API — must be set via riddleBoxCfg (config.cgi POST)
    configCgiKeys: ['AdvancedFeatures', 'CustomCarLogo'],

    // Set toggle value
    setToggle: function(key, val, element) {
        // Translate key if needed
        var apiKey = this.keyMap[key] || key;

        // Keys not in server.cgi API must go through config.cgi
        if (this.configCgiKeys.indexOf(apiKey) !== -1) {
            fetch('/cgi-bin/config.cgi', {
                method: 'POST',
                headers: {'Content-Type': 'application/x-www-form-urlencoded'},
                body: 'key=' + encodeURIComponent(apiKey) + '&val=' + encodeURIComponent(val)
            })
            .then(r => r.json())
            .then(data => {
                if (data.error) {
                    this.toast('Failed to update setting', 'error');
                    return;
                }
                var group = element.parentElement;
                group.querySelectorAll('.toggle').forEach(t => t.classList.remove('active'));
                element.classList.add('active');
                this.settings[apiKey] = parseInt(val);
                this.toast('Setting updated');
                if (key === 'CustomCarLogo') {
                    document.getElementById('logoUploadSection').style.display = val === '1' ? 'block' : 'none';
                }
            })
            .catch(() => this.toast('Failed to update setting', 'error'));
            return;
        }

        API.set(apiKey, val, (err, data) => {
            if (err) {
                this.toast('Failed to update setting', 'error');
                return;
            }
            // Update UI
            var group = element.parentElement;
            group.querySelectorAll('.toggle').forEach(t => t.classList.remove('active'));
            element.classList.add('active');
            this.settings[key] = parseInt(val);
            this.toast('Setting updated');

            // Handle special cases
            if (key === 'CustomCarLogo') {
                document.getElementById('logoUploadSection').style.display = val === '1' ? 'block' : 'none';
            }
        });
    },

    // Set numeric setting from input
    setSetting: function(inputId, key) {
        var value = document.getElementById(inputId).value;
        if (value === '') return;

        API.set(key, value, (err, data) => {
            if (err) {
                this.toast('Failed to update setting', 'error');
                return;
            }
            this.settings[key] = parseInt(value);
            this.toast('Setting updated');
        });
    },

    // Set text setting
    setTextSetting: function(key) {
        var value = document.getElementById(key).value;
        // Sanitize: only allow alphanumeric, spaces, dashes, underscores
        value = value.replace(/[^a-zA-Z0-9\s\-_]/g, '');
        if (value.length > 15) value = value.substring(0, 15);

        API.set(key, value, (err, data) => {
            if (err) {
                this.toast('Failed to update setting', 'error');
                return;
            }
            this.settings[key] = value;
            document.getElementById(key).value = value;
            this.toast('Setting updated');
        });
    },

    // Set select value
    setSelect: function(key, val) {
        API.set(key, val, (err, data) => {
            if (err) {
                this.toast('Failed to update setting', 'error');
                return;
            }
            this.settings[key] = val;
            this.toast('Setting updated');
        });
    },

    // Delete paired device
    deleteDevice: function(deviceId) {
        if (!confirm('Delete device ' + deviceId + '?\n\nNote: A restart is required for changes to take effect.')) return;

        API.deleteDevice(deviceId, (err, data) => {
            if (err) {
                this.toast('Failed to delete device', 'error');
                return;
            }
            this.deviceList = this.deviceList.filter(d => d.id !== deviceId);
            this.updateDeviceList();
            this.toast('Device deleted - restart required to apply changes');

            // Prompt user to restart
            if (confirm('Device deleted. Restart now to apply changes?')) {
                this.restart();
            }
        });
    },

    // Clear all devices
    clearAllDevices: function() {
        if (!confirm('Delete ALL paired devices?\n\nNote: A restart is required for changes to take effect.')) return;

        if (this.deviceList.length === 0) {
            this.toast('No devices to clear');
            return;
        }

        var devicesToDelete = this.deviceList.slice(); // Copy array
        var deletedCount = 0;
        var failedCount = 0;
        var totalDevices = devicesToDelete.length;
        var self = this;

        this.toast('Clearing ' + totalDevices + ' device(s)...');

        // Delete each device individually using the correct 'delDev' parameter
        devicesToDelete.forEach(function(device) {
            API.deleteDevice(device.id, function(err, data) {
                if (err) {
                    failedCount++;
                } else {
                    deletedCount++;
                }

                // Check if all deletions are complete
                if (deletedCount + failedCount === totalDevices) {
                    self.deviceList = [];
                    self.updateDeviceList();

                    if (failedCount > 0) {
                        self.toast('Cleared ' + deletedCount + '/' + totalDevices + ' devices (some failed)', 'error');
                    } else {
                        self.toast('All ' + deletedCount + ' device(s) cleared - restart required');
                    }

                    // Prompt user to restart
                    if (confirm('All devices cleared. Restart now to apply changes?')) {
                        self.restart();
                    }
                }
            });
        });
    },

    // Restart device
    restart: function() {
        if (!confirm('Restart device? This will disconnect any active session.')) return;
        this.doRestart();
    },

    // Restart without confirmation (used after factory reset)
    doRestart: function() {
        this.toast('Restarting device...');
        // Try CGI restart first, fall back to API command
        fetch('/cgi-bin/restart.cgi')
            .catch(() => {
                API.request('restart', null, null, () => {});
            });
    },

    // Factory reset
    factoryReset: function() {
        if (!confirm('FACTORY RESET? This will erase all settings and paired devices!')) return;
        if (!confirm('Are you SURE? This cannot be undone.')) return;

        API.resetApp((err, data) => {
            if (err) {
                this.toast('Reset failed', 'error');
                return;
            }
            this.toast('Factory reset complete');
            if (confirm('Restart device now to apply changes?')) {
                this.doRestart();
            } else {
                this.toast('Restart required for changes to take effect');
                setTimeout(() => this.loadData(), 1000);
            }
        });
    },

    // Reset to previous config
    resetConfig: function() {
        if (!confirm('Reset to previous configuration?')) return;

        API.reset((err, data) => {
            if (err) {
                this.toast('Reset failed', 'error');
                return;
            }
            this.toast('Configuration reset');
            this.loadData();
        });
    },

    // Restore factory defaults
    restoreDefaults: function() {
        if (!confirm('Restore factory default settings?')) return;

        API.request('resetApp', null, null, (err, data) => {
            if (err) {
                this.toast('Restore failed', 'error');
                return;
            }
            this.toast('Defaults restored');
            if (confirm('Restart device now to apply changes?')) {
                this.doRestart();
            } else {
                this.toast('Restart required for changes to take effect');
                setTimeout(() => this.loadData(), 1000);
            }
        });
    },

    // Load current CPU governor and populate dropdown
    loadGovernor: function() {
        fetch('/cgi-bin/governor.cgi')
            .then(r => r.json())
            .then(data => {
                var el = document.getElementById('cpuGovernor');
                if (!el) return;
                var avail = (data.available || '').trim().split(/\s+/).filter(Boolean);
                if (avail.length) {
                    el.innerHTML = '';
                    avail.forEach(function(gov) {
                        var opt = document.createElement('option');
                        opt.value = gov;
                        opt.textContent = gov;
                        el.appendChild(opt);
                    });
                }
                if (data.current) el.value = data.current;
            })
            .catch(function() {});
    },

    // Set CPU governor
    setGovernor: function(governor) {
        fetch('/cgi-bin/governor.cgi', {
            method: 'POST',
            body: governor
        })
        .then(r => r.json())
        .then(data => {
            if (data.current === governor) {
                this.toast('Governor set to ' + governor);
            } else {
                this.toast('Governor change failed', 'error');
            }
        })
        .catch(() => this.toast('Failed to set governor', 'error'));
    },

    // Download log file
    downloadLog: function(type) {
        var url = '/cgi-bin/logs.cgi?type=' + type;
        var filename = type + '_' + new Date().toISOString().slice(0,10) + '.txt';

        fetch(url)
            .then(r => r.blob())
            .then(blob => {
                var a = document.createElement('a');
                a.href = URL.createObjectURL(blob);
                a.download = filename;
                a.click();
                this.toast('Downloading ' + filename);
            })
            .catch(() => this.toast('Failed to download log', 'error'));
    },

    // Upload logo
    uploadLogo: function() {
        var fileInput = document.getElementById('logoFile');
        if (!fileInput.files.length) {
            this.toast('Please select a file', 'error');
            return;
        }

        var file = fileInput.files[0];
        if (!file.type.match('image/png')) {
            this.toast('Please select a PNG file', 'error');
            return;
        }

        API.uploadFile(file, 'carlogo.png', (err, data) => {
            if (err) {
                this.toast('Upload failed', 'error');
                return;
            }
            this.toast('Logo uploaded');
        });
    },

    // Update dashboard stats using BoxMonitor API
    updateStats: function() {
        API.getBoxMonitor((err, data) => {
            if (err || !data || !data.BoxMonitor) {
                console.log('[Stats] BoxMonitor error, falling back to sysinfo.cgi');
                this.updateStatsFallback();
                return;
            }
            var m = data.BoxMonitor;

            // Update dashboard stats
            this.setElementText('cpuUsage', Math.round(m.CpuRate) + '%');
            this.setElementText('memUsage', Math.round(m.MemRate) + '%');
            this.setElementText('cpuTemp', Math.round(m.CpuTemp) + '°C');
            this.setElementText('cpuFreq', m.CpuFreq + ' MHz');

            // WiFi throughput from BoxMonitor (already in KB/s)
            this.setElementText('netRxDash', m.WifiRX.toFixed(1) + ' KB/s');
            this.setElementText('netTxDash', m.WifiTX.toFixed(1) + ' KB/s');

            // Projection status
            this.setElementText('projectionType', m.MDLinkType || 'None');
            this.setElementText('huLinkType', m.HULinkType || 'None');

            // Fetch uptime, memory details, and total network stats (not in BoxMonitor)
            fetch('/cgi-bin/sysinfo.cgi')
                .then(r => r.json())
                .then(info => {
                    this.setElementText('uptime', this.formatUptime(info.uptime));
                    this.setElementText('memDetail', info.memUsed + ' / ' + info.memTotal + ' MB');
                    this.setElementText('netRxTotal', 'Total: ' + this.formatBytes(info.rx));
                    this.setElementText('netTxTotal', 'Total: ' + this.formatBytes(info.tx));
                })
                .catch(() => {});
        });
    },

    // Fallback to sysinfo.cgi if BoxMonitor fails
    updateStatsFallback: function() {
        fetch('/cgi-bin/sysinfo.cgi')
            .then(r => r.json())
            .then(data => {
                this.setElementText('cpuUsage', data.cpu + '%');
                this.setElementText('memUsage', data.mem + '%');
                this.setElementText('memDetail', data.memUsed + ' / ' + data.memTotal + ' MB');
                this.setElementText('cpuTemp', data.temp + '°C');
                this.setElementText('uptime', this.formatUptime(data.uptime));
            })
            .catch(() => {});
    },

    // Helper to safely set element text
    setElementText: function(id, text) {
        var el = document.getElementById(id);
        if (el) el.textContent = text;
    },

    // Helper to safely set element style
    setElementStyle: function(id, prop, value) {
        var el = document.getElementById(id);
        if (el) el.style[prop] = value;
    },

    // Refresh WiFi clients
    refreshWifiClients: function() {
        fetch('/cgi-bin/wifi_clients.cgi')
            .then(r => r.json())
            .then(data => {
                var container = document.getElementById('wifiClients');
                if (data.count === 0) {
                    container.innerHTML = '<p>No clients connected</p>';
                } else {
                    container.innerHTML = '<p>' + data.count + ' client(s) connected</p>' +
                        '<ul>' + data.clients.map(c => '<li>' + c + '</li>').join('') + '</ul>';
                }
            })
            .catch(() => {
                document.getElementById('wifiClients').innerHTML = '<p>Failed to load</p>';
            });
    },

    // ---- Terminal ----------------------------------------------------------

    // Wire up the terminal input (Enter to run, Up/Down for history)
    setupTerminal: function() {
        var input = document.getElementById('termInput');
        var form = document.getElementById('termForm');
        if (!input || !form) return;
        var self = this;

        // Run on Enter / on-screen keyboard "Go" / the Run button. The form's
        // submit event is far more reliable than a keydown handler on iOS
        // Safari, where Return often doesn't emit a usable keydown.
        form.addEventListener('submit', function(e) {
            e.preventDefault();
            self.runCommand(input.value);
            input.value = '';
        });

        // Arrow keys recall command history (desktop convenience).
        input.addEventListener('keydown', function(e) {
            if (e.key === 'ArrowUp') {
                e.preventDefault();
                self.recallHistory(-1, input);
            } else if (e.key === 'ArrowDown') {
                e.preventDefault();
                self.recallHistory(1, input);
            }
        });
        // Focus the input whenever the Terminal tab is opened (once enabled)
        document.querySelectorAll('.tab[data-tab="terminal"]').forEach(function(tab) {
            tab.addEventListener('click', function() {
                if (self.term.acked) setTimeout(function() { input.focus(); }, 0);
            });
        });
        this.setTermPrompt();
    },

    // Dismiss the danger warning and reveal the terminal (once per page load)
    ackTerminal: function() {
        this.term.acked = true;
        var warn = document.getElementById('termWarning');
        var body = document.getElementById('termBody');
        if (warn) warn.style.display = 'none';
        if (body) body.style.display = 'block';
        var input = document.getElementById('termInput');
        if (input) input.focus();
    },

    // Step through command history with the arrow keys
    recallHistory: function(dir, input) {
        var h = this.term.history;
        if (!h.length) return;
        this.term.histIndex += dir;
        if (this.term.histIndex < 0) this.term.histIndex = 0;
        if (this.term.histIndex >= h.length) {
            this.term.histIndex = h.length;
            input.value = '';
            return;
        }
        input.value = h[this.term.histIndex];
    },

    setTermPrompt: function() {
        var p = document.getElementById('termPrompt');
        if (p) p.textContent = this.term.cwd + ' #';
    },

    // Append a line/block to the terminal output, optionally styled
    appendTerm: function(text, cls) {
        var out = document.getElementById('termOutput');
        if (!out) return;
        var div = document.createElement('div');
        div.className = 'term-line' + (cls ? ' ' + cls : '');
        div.textContent = text;
        out.appendChild(div);
        out.scrollTop = out.scrollHeight;
    },

    clearTerminal: function() {
        var out = document.getElementById('termOutput');
        if (out) out.innerHTML = '';
    },

    // Send a command to term.cgi and render the result
    runCommand: function(cmd) {
        if (this.term.busy) {
            this.toast('A command is still running', 'error');
            return;
        }
        cmd = (cmd || '').replace(/\s+$/, '');
        // Echo the prompt + command into the scrollback
        this.appendTerm(this.term.cwd + ' # ' + cmd, 'term-cmd');
        if (cmd === '') { return; }

        // Client-side `clear` so it behaves like a real shell
        if (cmd === 'clear') { this.clearTerminal(); return; }

        // Record history
        this.term.history.push(cmd);
        this.term.histIndex = this.term.history.length;

        this.term.busy = true;
        var self = this;
        var input = document.getElementById('termInput');
        if (input) input.disabled = true;

        // Abort hung requests (interactive/long-running commands) after 60s
        var controller = (typeof AbortController !== 'undefined') ? new AbortController() : null;
        var timer = setTimeout(function() { if (controller) controller.abort(); }, 60000);

        // Body: line 1 = working directory, remaining = command
        var body = this.term.cwd + '\n' + cmd;

        fetch('/cgi-bin/term.cgi', {
            method: 'POST',
            headers: {'Content-Type': 'text/plain'},
            body: body,
            signal: controller ? controller.signal : undefined
        })
            .then(function(r) { return r.text(); })
            .then(function(text) {
                clearTimeout(timer);
                self.renderCommandResult(text);
            })
            .catch(function(err) {
                clearTimeout(timer);
                if (err && err.name === 'AbortError') {
                    self.appendTerm('[aborted after 60s — command still running on adapter]', 'term-err');
                } else {
                    self.appendTerm('[request failed: ' + (err && err.message ? err.message : err) + ']', 'term-err');
                }
            })
            .then(function() {
                self.term.busy = false;
                if (input) { input.disabled = false; input.focus(); }
            });
    },

    // Split term.cgi output into command output + metadata trailer
    renderCommandResult: function(text) {
        var marker = '\n###CPCTERM_META###';
        var idx = text.lastIndexOf(marker);
        var output = text, rc = null, newCwd = null;
        if (idx !== -1) {
            output = text.slice(0, idx);
            var meta = text.slice(idx + marker.length);   // "<rc>|<cwd>"
            var bar = meta.indexOf('|');
            if (bar !== -1) {
                rc = meta.slice(0, bar);
                newCwd = meta.slice(bar + 1);
            }
        }
        if (output.length) {
            this.appendTerm(output.replace(/\n$/, ''), rc && rc !== '0' ? 'term-err' : null);
        }
        if (newCwd) {
            this.term.cwd = newCwd;
            this.setTermPrompt();
        }
    },

    // Format uptime
    formatUptime: function(seconds) {
        var days = Math.floor(seconds / 86400);
        var hours = Math.floor((seconds % 86400) / 3600);
        var mins = Math.floor((seconds % 3600) / 60);
        if (days > 0) return days + 'd ' + hours + 'h';
        if (hours > 0) return hours + 'h ' + mins + 'm';
        return mins + 'm';
    },

    // Format bytes
    formatBytes: function(bytes) {
        if (bytes < 1024) return bytes + ' B';
        if (bytes < 1048576) return (bytes / 1024).toFixed(1) + ' KB';
        return (bytes / 1048576).toFixed(1) + ' MB';
    },

    // Show toast notification
    toast: function(message, type) {
        var toast = document.getElementById('toast');
        toast.textContent = message;
        toast.className = 'toast show' + (type === 'error' ? ' error' : '');
        setTimeout(() => toast.className = 'toast', 3000);
    },

    // Refresh all data (header button + page load)
    refreshAll: function() {
        this.loadData();
        this.loadFullConfig();
        this.toast('Refreshing...');
    },

    // Full config dump metadata — all 106 keys from binary analysis
    // s=status: A=ALIVE, D=DEAD, P=PASS-THROUGH | c=category | v=value map | bits=bitmask
    CONFIG_META: {
        // Integer keys (table index order)
        iAP2TransMode:              {d:0,  min:0,max:1,     s:'A',c:'conn',    n:'iAP2 link-layer framing mode — controls SYN negotiation params (cumulativeAckTimeout, maxRecvPacketLen). Most-referenced key (61 xrefs). Applies to both USB and BT transports.', v:{0:'Standard framing',1:'Compatible framing (longer ACK timeouts, smaller messages)'}},
        MediaQuality:               {d:1,  min:0,max:1,     s:'A',c:'audio',   n:'Audio sample rate', v:{0:'44.1 kHz',1:'48 kHz'}},
        MediaLatency:               {d:1000,min:300,max:2000,s:'A',c:'audio',   n:'A/V sync buffer (ms)'},
        UdiskMode:                  {d:1,  min:0,max:1,     s:'A',c:'conn',    n:'USB mass storage gadget — creates 8MB RAM FAT32 image with BoxHelper.apk, exposes via f_mass_storage composite gadget. WARNING: interferes with Android Auto', v:{0:'Disabled (USB for protocol only)',1:'Enabled (accessory,mass_storage)'}},
        LogMode:                    {d:1,  min:0,max:1,     s:'A',c:'system',  n:'Log verbosity', v:{0:'Quiet',1:'Verbose'}},
        BoxConfig_UI_Lang:          {d:0,  min:0,max:65535, s:'A',c:'system',  n:'UI language index into LangList'},
        BoxConfig_DelayStart:       {d:0,  min:0,max:120,   s:'A',c:'conn',    n:'Delay before USB init (seconds)', v:{0:'No delay'}},
        BoxConfig_preferSPSPPSType: {d:0,  min:0,max:1,     s:'D',c:'video',   n:'Legacy SPS/PPS type (superseded)', v:{0:'Type A',1:'Type B'}},
        NotCarPlayH264DecreaseMode: {d:0,  min:0,max:2,     s:'D',c:'video',   n:'Non-CarPlay bitrate ctrl (unimpl)', v:{0:'Off',1:'Mode 1',2:'Mode 2'}},
        NeedKeyFrame:               {d:0,  min:0,max:1,     s:'A',c:'video',   n:'Active IDR request on decode errors', v:{0:'Off — no IDR requests',1:'On — request IDR on errors'}},
        EchoLatency:                {d:320,min:20,max:2000, s:'A',c:'audio',   n:'Echo cancellation delay (ms)', v:{320:'Sentinel — enables two-mode AEC'}},
        DisplaySize:                {d:0,  min:0,max:3,     s:'P',c:'display', n:'CarPlay display size (server.cgi only)', v:{0:'Auto',1:'Small',2:'Medium',3:'Large'}},
        UseBTPhone:                 {d:0,  min:0,max:1,     s:'A',c:'audio',   n:'Bluetooth phone call routing', v:{0:'Route calls through adapter',1:'Route calls through phone BT'}},
        MicGainSwitch:              {d:0,  min:0,max:1,     s:'A',c:'audio',   n:'WebRTC AGC (automatic gain control) — NOT simple analog gain. Controls software-level gain normalization in mic processing pipeline.', v:{0:'AGC off (raw mic level)',1:'AGC enabled (auto-normalize mic level)'}},
        CustomFrameRate:            {d:0,  min:0,max:60,    s:'A',c:'video',   n:'FPS override', v:{0:'Auto (~30 FPS)'}},
        NeedAutoConnect:            {d:1,  min:0,max:1,     s:'A',c:'conn',    n:'Auto-reconnect last device', v:{0:'Off',1:'On — reconnect on startup'}},
        BackgroundMode:             {d:0,  min:0,max:1,     s:'A',c:'display', n:'Background UI behavior', v:{0:'Show adapter connection UI',1:'Hide adapter connection UI'}},
        HudGPSSwitch:               {d:0,  min:0,max:1,     s:'A',c:'gps',     n:'GPS forwarding master gate — factory default DISABLED. Requires GNSSCapability>0 from host BoxSettings to have any effect. Controls NMEA sentence forwarding via iAP2 LocationInformation.', v:{0:'Off (factory default)',1:'On — forward HU GPS via iAP2'}},
        CarDate:                    {d:0,  min:0,max:1,     s:'A',c:'system',  n:'Time sync enable — controls whether adapter accepts syncTime from host BoxSettings. When enabled, adapter applies host time with +8h CST offset.', v:{0:'Disabled (use adapter RTC/NTP)',1:'Enabled (accept syncTime from host)'}},
        WiFiChannel:                {d:0,  min:0,max:200,   s:'A',c:'network', n:'WiFi channel — 0=auto (firmware picks best). Invalid values fall back to 36. Triggers async WiFi+BT restart. Adapter reports supported channels in WifiChannelList.', v:{0:'Auto (firmware selects)'}},
        AutoPlauMusic:              {d:0,  min:0,max:1,     s:'A',c:'conn',    n:'Auto-start music on connect', v:{0:'Off',1:'On — resume playback'}},
        MouseMode:                  {d:1,  min:0,max:1,     s:'P',c:'display', n:'Touch input mode (server.cgi only)', v:{0:'Absolute',1:'Relative'}},
        CustomCarLogo:              {d:0,  min:0,max:1,     s:'A',c:'display', n:'Custom boot logo upload — uses system() for file operations (command injection risk). Controls whether factory logo or user-uploaded PNG is displayed.', v:{0:'Factory logo',1:'Custom uploaded PNG (via system())'}},
        VideoBitRate:               {d:0,  min:0,max:20,    s:'A',c:'video',   n:'H.264 bitrate cap level — 0=auto (adaptive, phone decides), 1-20=fixed cap level mapped to bps value in ARMadb-driver lookup table. Higher values = higher bitrate.', v:{0:'Auto (adaptive, phone decides)'}},
        VideoResolutionHeight:      {d:0,  min:0,max:4096,  s:'A',c:'video',   n:'Video height override', v:{0:'Auto (phone decides)'}},
        VideoResolutionWidth:       {d:0,  min:0,max:4096,  s:'A',c:'video',   n:'Video width override', v:{0:'Auto (phone decides)'}},
        UDiskPassThrough:           {d:1,  min:0,max:1,     s:'D',c:'conn',    n:'USB disk passthrough (superseded)', v:{0:'Off',1:'On'}},
        AndroidWorkMode:            {d:1,  min:0,max:5,     s:'A',c:'conn',    n:'Phone link daemon selector — triggers phone_link_deamon.sh to start/stop protocol daemons. Resets to 0 on phone disconnect. Host must re-send on every connection.', v:{0:'Idle (kill running daemon)',1:'AndroidAuto (ARMAndroidAuto+hfpd)',2:'CarLife (Baidu)',3:'AndroidMirror (screencast, direct fork)',4:'HiCar (Huawei, 9 shared libs)',5:'ICCOA'}},
        CarDrivePosition:           {d:0,  min:0,max:1,     s:'A',c:'display', n:'Driving position — affects CarPlay UI layout mirroring and dock side placement. Also influences day/night theme transitions.', v:{0:'Left-hand drive (dock on left)',1:'Right-hand drive (dock on right)'}},
        AndroidAutoWidth:           {d:0,  min:0,max:4096,  s:'P',c:'aa',      n:'AA video width (boot script)', v:{0:'Auto'}},
        AndroidAutoHeight:          {d:0,  min:0,max:4096,  s:'P',c:'aa',      n:'AA video height (boot script)', v:{0:'Auto'}},
        ScreenDPI:                  {d:0,  min:0,max:480,   s:'A',c:'display', n:'Display DPI (written to /tmp/screen_dpi)', v:{0:'Auto'}},
        KnobMode:                   {d:0,  min:0,max:1,     s:'P',c:'display', n:'Rotary knob mapping (server.cgi only)', v:{0:'Off',1:'On'}},
        NaviAudio:                  {d:0,  min:0,max:2,     s:'A',c:'audio',   n:'Navigation audio mixing mode — controls how nav voice prompts are combined with media audio on the USB output.', v:{0:'Mixed with media (single stream)',1:'Separate USB channel (dual-stream)',2:'Adapter-side ducking (attenuate media during nav)'}},
        ScreenPhysicalW:            {d:0,  min:0,max:1000,  s:'A',c:'display', n:'Display width in mm (AirPlay)', v:{0:'Auto'}},
        ScreenPhysicalH:            {d:0,  min:0,max:1000,  s:'A',c:'display', n:'Display height in mm (AirPlay)', v:{0:'Auto'}},
        CallQuality:                {d:1,  min:0,max:2,     s:'D',c:'audio',   n:'Call quality — REMOVED from UI. Firmware bug: does not update VoiceQuality. VoiceQuality itself only affects AA HFP codec, not CarPlay (iPhone controls format via AirPlay)', v:{0:'Normal (8kHz NB)',1:'Clear (16kHz WB)',2:'HD (reserved)'}},
        VoiceQuality:               {d:1,  min:0,max:2,     s:'D',c:'audio',   n:'Voice/call quality (AA HFP only). No effect on CarPlay — iPhone sends 16kHz wideband regardless', v:{0:'Normal (8kHz NB)',1:'Clear (16kHz WB)',2:'HD (32kHz SWB)'}},
        AutoUpdate:                 {d:1,  min:0,max:1,     s:'A',c:'system',  n:'OTA auto-update', v:{0:'Disabled',1:'Enabled'}},
        LastBoxUIType:              {d:1,  min:0,max:2,     s:'D',c:'system',  n:'Last session type (vestigial)', v:{0:'None',1:'CarPlay',2:'Android Auto'}},
        BoxSupportArea:             {d:0,  min:0,max:1,     s:'A',c:'system',  n:'Region flag — affects iAP2 identification params', v:{0:'Global (default)',1:'China (zh lang hint, HiCar context)'}},
        HNPInterval:                {d:10, min:0,max:1000,  s:'D',c:'conn',    n:'USB HNP interval ms (vestigial OTG)'},
        lightType:                  {d:3,  min:1,max:3,     s:'D',c:'system',  n:'LED pattern (colorLightDaemon?)', v:{1:'Pattern 1',2:'Pattern 2',3:'Pattern 3'}},
        MicType:                    {d:0,  min:0,max:2,     s:'A',c:'audio',   n:'Microphone source', v:{0:'Car mic (head unit)',1:'Adapter built-in mic',2:'Phone mic'}},
        RepeatKeyframe:             {d:0,  min:0,max:1,     s:'A',c:'video',   n:'Cached IDR resend', v:{0:'Off',1:'On — resend last IDR on underrun'}},
        BtAudio:                    {d:0,  min:0,max:1,     s:'A',c:'audio',   n:'Audio transport path — selects USB bulk PCM vs Bluetooth A2DP source. Set by host via cmd 22/23.', v:{0:'USB bulk PCM (default, low latency)',1:'Bluetooth A2DP source (higher latency, wireless)'}},
        MicMode:                    {d:0,  min:0,max:4,     s:'A',c:'audio',   n:'WebRTC noise suppression mode', v:{0:'Off',1:'Low',2:'Moderate',3:'High',4:'Very High'}},
        SpsPpsMode:                 {d:0,  min:0,max:3,     s:'A',c:'video',   n:'SPS/PPS H.264 parameter set handling in ARMadb-driver NAL forwarding layer. Init-read only — requires process restart to take effect.', v:{0:'Passthrough (forward NALs as-is from phone)',1:'Re-inject (prepend cached SPS+PPS before every IDR)',2:'Cache for recovery (passthrough + replay SPS+PPS+IDR on host error 0x0C)',3:'Repeat every packet (SPS+PPS before every frame, ~30-40B overhead)'}},
        MediaPacketLen:             {d:200,min:200,max:20000,s:'A',c:'audio',   n:'Media audio USB bulk size (bytes)'},
        TtsPacketLen:               {d:200,min:200,max:40000,s:'A',c:'audio',   n:'TTS audio USB bulk size (bytes)'},
        VrPacketLen:                {d:200,min:200,max:40000,s:'A',c:'audio',   n:'Voice recognition USB bulk size (bytes)'},
        TtsVolumGain:               {d:0,  min:0,max:1,     s:'A',c:'audio',   n:'TTS volume boost', v:{0:'Normal',1:'Boosted'}},
        VrVolumGain:                {d:0,  min:0,max:1,     s:'A',c:'audio',   n:'VR (voice recognition) mic gain boost — NOT call voice gain', v:{0:'Normal',1:'Boosted'}},
        CarLinkType:                {d:30, min:1,max:30,    s:'A',c:'conn',    n:'Protocol override — ONLY consulted for USB PID 0x68. CPC200-CCPA PIDs (0x1520/0x1521) bypass this key entirely. Value 30 enables full auto-detect.', v:{1:'CarPlay',2:'AndroidAuto',3:'HiCar',4:'CarLife',5:'ICCOA',6:'Wired AA',7:'Wired HiCar',8:'Wireless HiCar',20:'ICCOA (alt, msg 0xA1)',30:'Auto-detect all (BT scan, rfcomm check)'}},
        SendHeartBeat:              {d:1,  min:0,max:1,     s:'A',c:'conn',    n:'USB keepalive heartbeat', v:{0:'Off (DANGEROUS — adapter may hang)',1:'On — 2s heartbeat'}},
        SendEmptyFrame:             {d:1,  min:0,max:1,     s:'A',c:'video',   n:'Timing packets during video gaps', v:{0:'Off',1:'On — send empty frames'}},
        autoDisplay:                {d:1,  min:0,max:2,     s:'P',c:'display', n:'Auto-switch to adapter (server.cgi only)', v:{0:'Off',1:'Auto',2:'Always'}},
        USBConnectedMode:           {d:0,  min:0,max:2,     s:'A',c:'conn',    n:'USB gadget functions exposed to host (start_mtp.sh)', v:{0:'MTP + ADB',1:'MTP only',2:'ADB only'}},
        USBTransMode:               {d:0,  min:0,max:1,     s:'A',c:'conn',    n:'USB Zero-Length Packet for AOA (Android Auto). Fixes bulk transfer stalls on strict USB controllers (start_aoa.sh)', v:{0:'ZLP off (standard)',1:'ZLP on (accZLP=1)'}},
        ReturnMode:                 {d:0,  min:0,max:1,     s:'A',c:'display', n:'Back button behavior', v:{0:'Return to adapter UI',1:'Return to head unit'}},
        LogoType:                   {d:0,  min:0,max:3,     s:'A',c:'display', n:'CarPlay device icon shown on iPhone — selects which airplay_*.conf is loaded at CarPlay negotiation. Set via firmware cmd 0x09.', v:{0:'Default icon',1:'Car/OEM icon (airplay_car.conf)',2:'Brand icon',3:'No icon (airplay_none.conf)'}},
        BackRecording:              {d:0,  min:0,max:1,     s:'A',c:'system',  n:'Background mic for voice wake-word detection ("Hey Siri"/"OK Google") when CarPlay/AA is backgrounded. Keeps mic capture active even when projection is not in foreground.', v:{0:'Disabled (mic stops when backgrounded)',1:'Enabled (mic stays active for wake-word)'}},
        FastConnect:                {d:0,  min:0,max:1,     s:'A',c:'conn',    n:'Fast reconnect (skip BT scan)', v:{0:'Off — full BT scan',1:'On — skip scan (4-condition gate)'}},
        WiredConnect:               {d:1,  min:0,max:1,     s:'A',c:'conn',    n:'Wired connection fallback', v:{0:'Wireless only',1:'Wired fallback enabled'}},
        ImprovedFluency:            {d:0,  min:0,max:1,     s:'D',c:'video',   n:'DEAD — intended to increase USB bulk transfer buffers and adjust pcm_get_buffer_size. String count of 1 in every binary (config table only). server.cgi has 3 refs but pure pass-through get/set. Zero GetBoxConfig callers.', v:{0:'Off',1:'On (no effect — never implemented)'}},
        NaviVolume:                 {d:0,  min:0,max:100,   s:'A',c:'audio',   n:'Navigation voice volume (0-100) — independent mixer level for nav TTS output. Only effective when NaviAudio=1 (separate channel) or NaviAudio=2 (ducking).'},
        OriginalResolution:         {d:0,  min:0,max:1,     s:'A',c:'video',   n:'Phone native resolution', v:{0:'Off — use configured resolution',1:'On — use phone native'}},
        AutoConnectInterval:        {d:0,  min:0,max:60,    s:'A',c:'conn',    n:'Reconnect timer interval (seconds)', v:{0:'Disabled'}},
        AutoResetUSB:               {d:1,  min:0,max:1,     s:'A',c:'conn',    n:'USB power-cycle on error', v:{0:'Disabled',1:'Enabled'}},
        HiCarConnectMode:           {d:0,  min:0,max:1,     s:'A',c:'conn',    n:'HiCar discovery/pairing mode — consumed by ARMHiCar (MSDP event handler) and bluetoothDaemon (BLE advertising). Only relevant for Huawei/HarmonyOS devices.', v:{0:'QR code + PIN pairing (default)',1:'BLE-only fast reconnect (inferred from string adjacency)'}},
        GNSSCapability:             {d:0,  min:0,max:65535, s:'A',c:'gps',     n:'GNSS capability bitmask', bits:{0:'GPS ($GPGGA/$GPRMC)',1:'GLONASS ($GNGGA/$GNRMC)',2:'Galileo',3:'BeiDou'}, v:{0:'No GNSS',3:'GPS+GLONASS'}},
        DashboardInfo:              {d:1,  min:0,max:7,     s:'A',c:'gps',     n:'Dashboard info bitmask', bits:{0:'Media info',1:'Vehicle info',2:'Route info'}, v:{0:'None',1:'Media only',3:'Media+Vehicle',5:'Media+Route',7:'All'}},
        AudioMultiBusMode:          {d:1,  min:0,max:1,     s:'D',c:'audio',   n:'Multi-bus audio (unimpl)', v:{0:'Off',1:'On (no effect)'}},
        DayNightMode:               {d:2,  min:0,max:2,     s:'A',c:'display', n:'Theme mode', v:{0:'Auto (follow head unit)',1:'Day (light)',2:'Night (dark)'}},
        InternetHotspots:           {d:0,  min:0,max:1,     s:'D',c:'network', n:'WiFi sharing (single radio — impossible)', v:{0:'Off',1:'On (no effect)'}},
        UseUartBLE:                 {d:0,  min:0,max:1,     s:'A',c:'network', n:'BLE software path — kernel HCI stack vs direct UART I/O. Direct UART bypasses BlueZ/hci0 and uses RiddleBluetoothService_Interface_UartBLE.', v:{0:'Kernel HCI stack (hci0, standard BlueZ)',1:'Direct UART I/O (RiddleBluetoothService_Interface_UartBLE)'}},
        WiFiP2PMode:                {d:0,  min:0,max:1,     s:'A',c:'network', n:'WiFi mode — SoftAP uses hostapd, P2P uses wpa_cli p2p_group_add (SSID=DIRECT-*). NXP cards force P2P. Realtek (A15W) defaults SoftAP', v:{0:'SoftAP (hostapd, standard AP)',1:'P2P Wi-Fi Direct (wpa_supplicant GO, DIRECT-* SSID)'}},
        DuckPosition:               {d:0,  min:0,max:2,     s:'A',c:'display', n:'Dock position', v:{0:'Left',1:'Right',2:'Bottom'}},
        AdvancedFeatures:           {d:0,  min:0,max:1,     s:'A',c:'conn',    n:'Legacy naviScreenInfo gate — REDUNDANT if host sends naviScreenInfo in BoxSettings (firmware bypasses this check at 0x16e64). Only needed on legacy path without naviScreenInfo. Also advertises "naviScreen" in boxInfo supportFeatures.', v:{0:'Off (host must send naviScreenInfo in BoxSettings for nav video)',1:'On (legacy path: adapter reads naviScreenWidth/Height/FPS from riddle.conf)'}},
        // String keys
        CarBrand:                   {d:'',                   s:'A',c:'brand',   n:'OEM brand (CMD INJECTION risk via sprintf→system)'},
        CarModel:                   {d:'',                   s:'A',c:'brand',   n:'Vehicle model string'},
        BluetoothName:              {d:'',                   s:'A',c:'brand',   n:'BT adapter name (read-only, set by firmware)'},
        WifiName:                   {d:'',                   s:'A',c:'brand',   n:'WiFi AP name (read-only, set by firmware)'},
        CustomBluetoothName:        {d:'',                   s:'A',c:'brand',   n:'Custom BT name (CMD INJECTION via system)'},
        CustomWifiName:             {d:'',                   s:'A',c:'brand',   n:'Custom WiFi name (CMD INJECTION via system)'},
        LastPhoneSpsPps:            {d:'',                   s:'D',c:'video',   n:'Cached SPS/PPS NAL data (vestigial)'},
        CustomId:                   {d:'',                   s:'P',c:'brand',   n:'OEM identifier (CGI only)'},
        LastConnectedDevice:        {d:'',                   s:'A',c:'conn',    n:'Last phone MAC address for reconnect'},
        IgnoreUpdateVersion:        {d:'',                   s:'A',c:'system',  n:'OTA version string to skip'},
        CustomBoxName:              {d:'',                   s:'A',c:'brand',   n:'Adapter name for mDNS/BT discovery'},
        WifiPassword:               {d:'12345678',           s:'A',c:'network', n:'WiFi hotspot password'},
        BrandName:                  {d:'',                   s:'A',c:'brand',   n:'Brand WiFi/BT name (factory commission)'},
        BrandBluetoothName:         {d:'',                   s:'A',c:'brand',   n:'Brand BT name (factory commission)'},
        BrandWifiName:              {d:'',                   s:'A',c:'brand',   n:'Brand WiFi name (factory commission)'},
        BrandServiceURL:            {d:'',                   s:'D',c:'brand',   n:'Brand cloud URL (vestigial)'},
        BoxIp:                      {d:'',                   s:'D',c:'network', n:'Config IP (vestigial — hardcoded 192.168.43.1)'},
        USBProduct:                 {d:'',                   s:'A',c:'brand',   n:'USB iProduct descriptor (commission 0x70)'},
        USBManufacturer:            {d:'',                   s:'A',c:'brand',   n:'USB iManufacturer descriptor (commission 0x70)'},
        USBPID:                     {d:'',                   s:'A',c:'brand',   n:'USB idProduct hex (commission 0x70)'},
        USBVID:                     {d:'',                   s:'A',c:'brand',   n:'USB idVendor hex (commission 0x70)'},
        USBSerial:                  {d:'',                   s:'A',c:'brand',   n:'USB iSerialNumber (commission 0x70)'},
        oemName:                    {d:'',                   s:'D',c:'brand',   n:'OEM identifier (vestigial)'},
        BrandWifiChannel:           {d:'',                   s:'A',c:'network', n:'Brand WiFi channel list for hostapd'},
        // Array keys
        DevList:                    {d:[],                   s:'A',c:'conn',    n:'Paired devices JSON array'},
        DeletedDevList:             {d:[],                   s:'A',c:'conn',    n:'Removed devices JSON array'},
        LangList:                   {d:[],                   s:'P',c:'system',  n:'UI language list JSON array'}
    },

    CATEGORY_LABELS: {
        video:   'Video / H.264',
        audio:   'Audio',
        conn:    'Connection / USB',
        display: 'Display / UI',
        aa:      'Android Auto',
        gps:     'GPS / Dashboard',
        network: 'Network / Wireless',
        system:  'System',
        brand:   'Branding / Identity'
    },

    // Load full config dump from config.cgi?mode=full
    loadFullConfig: function() {
        var container = document.getElementById('configDump');
        if (!container) return;
        container.innerHTML = '<p class="loading">Loading 106 keys...</p>';

        fetch('/cgi-bin/config.cgi?mode=full')
            .then(function(r) {
                if (!r.ok) throw new Error('HTTP ' + r.status);
                return r.text();
            })
            .then(function(text) {
                console.log('[Config] Raw response (' + text.length + ' bytes):', text.substring(0, 300));
                var data;
                try {
                    data = JSON.parse(text);
                } catch (e) {
                    console.error('[Config] JSON parse error:', e.message, 'Raw:', text.substring(0, 500));
                    throw new Error('JSON parse: ' + e.message);
                }
                App.renderConfigDump(data);
            })
            .catch(function(err) {
                console.error('[Config] loadFullConfig failed:', err);
                // Fallback: render table with defaults from CONFIG_META (no live values)
                App.renderConfigDump({});
                App.toast('Config dump: using defaults (' + err.message + ')', 'error');
            });
    },

    // Render the full config dump as categorized tables
    renderConfigDump: function(data) {
        var container = document.getElementById('configDump');
        if (!container) return;

        var meta = this.CONFIG_META;
        var cats = this.CATEGORY_LABELS;

        // Group keys by category
        var groups = {};
        Object.keys(cats).forEach(function(c) { groups[c] = []; });

        Object.keys(meta).forEach(function(key) {
            var m = meta[key];
            var cat = m.c;
            if (!groups[cat]) groups[cat] = [];
            groups[cat].push(key);
        });

        var html = '';
        var catOrder = ['video','audio','conn','display','aa','gps','network','system','brand'];

        catOrder.forEach(function(cat) {
            var keys = groups[cat];
            if (!keys || !keys.length) return;

            html += '<div class="config-category">';
            html += '<h3>' + App.escapeHtml(cats[cat]) + '</h3>';
            html += '<table class="config-table"><thead><tr>';
            html += '<th>Key</th><th>Value</th><th>Default</th><th>Range</th><th>Status</th><th>Description</th>';
            html += '</tr></thead><tbody>';

            keys.forEach(function(key) {
                var m = meta[key];
                var val = data[key];
                var valStr, valClass;

                if (val === undefined || val === null) {
                    // Distinguish null types by what the key's default is
                    if (typeof m.d === 'string') {
                        // String key with empty default — never configured, expected
                        valStr = '<span class="val-unset">unset</span>';
                        valClass = 'val-default';
                    } else if (Array.isArray(m.d)) {
                        // Array key — riddleBoxCfg can't read it
                        valStr = '<span class="val-unavail">unavailable</span>';
                        valClass = 'val-default';
                    } else {
                        // Integer key returning null — read error
                        valStr = '<span class="val-error">read error</span>';
                        valClass = 'val-default';
                    }
                } else {
                    valStr = App.escapeHtml(JSON.stringify(val));
                    var changed = (JSON.stringify(val) !== JSON.stringify(m.d));
                    valClass = changed ? 'val-changed' : 'val-default';
                }

                var statusClass = m.s === 'A' ? 'badge-alive' : (m.s === 'D' ? 'badge-dead' : 'badge-pass');
                var statusLabel = m.s === 'A' ? 'ALIVE' : (m.s === 'D' ? 'DEAD' : 'PASS');
                var rangeStr = (m.min !== undefined && m.max !== undefined) ? m.min + '-' + m.max : '';
                var defStr = App.escapeHtml(JSON.stringify(m.d));

                // Make key name clickable if value descriptions exist
                var hasDetail = (m.v && Object.keys(m.v).length > 0) || m.bits;
                var keyHtml = hasDetail
                    ? '<a class="key-link" data-key="' + App.escapeHtml(key) + '">' + App.escapeHtml(key) + '</a>'
                    : App.escapeHtml(key);

                html += '<tr>';
                html += '<td class="key-name">' + keyHtml + '</td>';
                html += '<td class="' + valClass + '">' + valStr + '</td>';
                html += '<td class="val-default">' + defStr + '</td>';
                html += '<td>' + rangeStr + '</td>';
                html += '<td><span class="badge ' + statusClass + '">' + statusLabel + '</span></td>';
                html += '<td class="key-desc">' + App.escapeHtml(m.n) + '</td>';
                html += '</tr>';
                // Hidden detail row for value descriptions
                if (hasDetail) {
                    html += '<tr class="detail-row" id="detail-' + key + '" style="display:none">';
                    html += '<td colspan="6">' + App.buildValueDetail(m, val) + '</td>';
                    html += '</tr>';
                }
            });

            html += '</tbody></table></div>';
        });

        container.innerHTML = html;

        // Attach click handlers for expandable key details
        container.querySelectorAll('.key-link').forEach(function(link) {
            link.addEventListener('click', function() {
                var row = document.getElementById('detail-' + this.dataset.key);
                if (row) {
                    row.style.display = row.style.display === 'none' ? 'table-row' : 'none';
                    this.classList.toggle('expanded');
                }
            });
        });
    },

    // Build the value detail HTML for expandable rows
    buildValueDetail: function(m, currentVal) {
        var html = '<div class="value-detail">';

        // Bitmask display
        if (m.bits) {
            html += '<div class="detail-section"><span class="detail-label">Bitmask:</span>';
            var bits = m.bits;
            Object.keys(bits).forEach(function(bit) {
                var bitNum = parseInt(bit);
                var isSet = (typeof currentVal === 'number') && ((currentVal >> bitNum) & 1);
                html += '<span class="bit-item' + (isSet ? ' bit-set' : '') + '">';
                html += 'bit ' + bit + ': ' + App.escapeHtml(bits[bit]);
                html += isSet ? ' [SET]' : ' [0]';
                html += '</span>';
            });
            html += '</div>';
        }

        // Value map display
        if (m.v) {
            html += '<div class="detail-section"><span class="detail-label">Values:</span>';
            var vals = m.v;
            Object.keys(vals).forEach(function(k) {
                var isCurrent = (currentVal !== null && currentVal !== undefined && String(currentVal) === k);
                html += '<span class="val-item' + (isCurrent ? ' val-active' : '') + '">';
                html += '<span class="val-key">' + App.escapeHtml(k) + '</span> ';
                html += App.escapeHtml(vals[k]);
                html += '</span>';
            });
            html += '</div>';
        }

        html += '</div>';
        return html;
    },

    // HTML escape for XSS safety
    escapeHtml: function(str) {
        if (str === null || str === undefined) return '';
        return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
    }
};

// Initialize on load
document.addEventListener('DOMContentLoaded', () => App.init());
