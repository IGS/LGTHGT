Ext.Loader.setConfig({
    enabled: true,
    paths: {
        'Ext.ux': 'ux/'
    }
});

Ext.require('Ext.ux.CheckColumn');

Ext.onReady(function(){

    // Path to script to populate the form with relevant info
    var EXTRACT_METADATA_URL = '/cgi-bin/build_metadata_table.cgi'; 
    // Path to script to populate the form with relevant info
    var INIT_LGTVIEW_URL = '/cgi-bin/build_custom_LGTView.cgi'; 

    var table = Ext.create('Ext.data.Store', {
        storeId:'table',
        fields: ['name', 'filter', 'pie', 'id', 'operator'],
        proxy: {
            type: 'ajax',
            url: EXTRACT_METADATA_URL,
            noCache: false,
            actionMethods: {
                read: 'POST'
            },
            reader: {
                type: 'json',
                root: 'root'
            }
        },
        autoLoad: false
    });

    var grid = Ext.create('Ext.grid.Panel', {
        store: table,
        selType: 'cellmodel',
        forcefit: true,
        columns: [
            {text: "Metadata", width: 150, dataIndex: 'name', flex: 1},
            {
            xtype: 'checkcolumn',
            text: 'Pie Graph',
            dataIndex: 'pie',
            id: 'pie',
            align: 'center',
            listeners: {
                'checkchange': function(col, idx, isChecked) {
                    var rec = grid.store.getAt(idx);
                    rec.set("filter", false);
                    rec.set("operator", 'NA');
                }
            }
            },
            {
            xtype: 'checkcolumn',
            text: 'Filter',
            dataIndex: 'filter',
            align: 'center',
            listeners: {
                'checkchange': function(col, idx, isChecked) {
                    var rec = grid.store.getAt(idx);
                    rec.set("pie", false);
                    if(rec.get("filter") === false) {
                        rec.set("operator", 'NA');
                    } else {
                        rec.set("operator", 'matches');
                    }
                }
            }
            },
            {
            text: "Comparison Operator", 
            width: 150, 
            dataIndex: 'operator',
            align: 'center',
            }
        ],
        columnLines: true,
        frame: true,
        title: 'Configure Pie Graphs and Filters',
        listeners: {
            cellclick: function(view, td, cellIndex, record, tr, rowIndex, e, eOpts){
                if(cellIndex == 3){
                    if(record.get('filter') === true){
                        if(record.get('operator') == 'matches'){
                            record.set('operator', '<');
                        } 
                        else if(record.get('operator') == '<'){
                            record.set('operator', '>');
                        }
                        else{
                            record.set('operator', 'matches');
                        }
                    }
                }
            }
        }
    });

    var middlepanel = Ext.create('Ext.panel.Panel', ({
        region: 'center',
        layout: 'fit',
        items: [grid]
    }));

    var submitSRA = Ext.create('Ext.Button', {
        text: 'Extract Metadata',
        id: 'submit_button',
        bodyPadding: 20,
        width: 100,
        style: { marginLeft: '15px' },
        handler: function() {
            loadMetadata();
        }
    });

    var loadLGTView = Ext.create('Ext.Button', {
        text: 'Load LGTView',
        id: 'load_button',
        bodyPadding: 20,
        width: 100,
        style: { marginLeft: '15px' },
        handler: function() {
            initLGTView();
        }
    });

    var form = Ext.create('Ext.form.field.Text', ({
        id: 'sra_list',
        bodyPadding: 10,
        width: 570,
        labelWidth: 230,
        fieldLabel: 'List File of Sequence Read Archive IDs',
    }));
    
    var toppanel =  Ext.create('Ext.form.Panel', ({
        frame: true,
        region: 'north',
        title: 'LGTView Generator',
        defaultType: 'textfield',
        layout: {
            type: 'hbox',
            pack: 'center'
        },
        items: [form,submitSRA]
    }));

    var lastpanel =  Ext.create('Ext.panel.Panel', ({
        frame: true,
        region: 'south',
        layout: {
            type: 'hbox',
            pack: 'center'
        },
        items: [loadLGTView]
    }));

    var vp = new Ext.Viewport({
        layout: 'border',
        autoScroll: true,
        //defaults: {split: true},
        items: [toppanel,middlepanel,lastpanel]
    });

    vp.doLayout();

    var metadata_loaded = '';

    function loadMetadata(){
        var val = Ext.ComponentQuery.query('#sra_list')[0].getValue();
        var conf = {
            'file': val
        }
        if(val){
            Ext.getCmp('submit_button').disable();
            table.proxy.extraParams = conf;
            table.load();
            metadata_loaded = 'yes';
            Ext.getCmp('submit_button').enable();
        }
    }

    function initLGTView(){

	var data = new Array();
	var records = table.getRange();
	for (var i = 0; i < records.length; i++) {
		data.push(records[i].data);
	}

        var conf = {
            dat: Ext.JSON.encode(data),
        }

        if(metadata_loaded == 'yes'){

            Ext.Ajax.request({
                url: INIT_LGTVIEW_URL,
                timeout: 600000,
		params: conf,
                success: function(response) { 
                    var res = Ext.JSON.decode(response.responseText,true);
                    if(res) {
                        vp.setLoading('Loading LGTView. Please navigate to localhost:8080 to view your new instance of LGTView once this message disappears.');
                    } else {
                        vp.setLoading(false);
                    }
                }
            });

        } else {
            alert('Please configure metadata before loading');
        }
    }
});
