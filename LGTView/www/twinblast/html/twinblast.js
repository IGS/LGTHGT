Ext.onReady(function(){

	// Path to guiblast CGI script
	var GUIBLAST_URL = '/cgi-bin/guiblast.cgi'; 

	// Path to TwinBLAST DB access component for annotation/curation
	var CURATION_URL = '/cgi-bin/twinblastDB.cgi'; 

	// Path to TwinBLAST DB access component for annotation/curation
	var REPORT_URL = '/cgi-bin/generateReport.cgi'; 

    // Pull out what's in the URL
    var vars = getUrlVars();

    var id = vars.id ? unescape(vars.id) : undefined;
    var qlist = vars.qlist ? unescape(vars.qlist) : undefined;
    // We need these three if we're going to use a single file
    var file = vars.file ? unescape(vars.file) : undefined;
    var list = vars.list ? unescape(vars.list) : undefined;
    var left_suff = vars.leftsuff ? vars.leftsuff : '/1';
    var right_suff = vars.rightsuff ? vars.rightsuff : '/2';

    // We'll need these 2 if we're using multiple files
    var left_file = vars.leftfile ? unescape(vars.leftfile) : undefined;
    var right_file = vars.rightfile ? unescape(vars.rightfile) : undefined;

    //If we have an ID and a file we'll start with the form collapsed
    var collapse_form = false;
    var single_file = true;

    var runner = new Ext.util.TaskRunner();
    var checkStatusTask = runner.newTask({
        run: function(conf) { checkStatus(conf);} ,
        interval: 10000
    });


    if(id && (file || list)) {
        collapse_form = true;
        single_file = true;
    }
    if(id && left_file && right_file) {
        collapse_form = true;
    }
    var show_list = true;
    if(!id && (file || list)) {
        single_file = true,
        show_list = true;
    }

	if(qlist) {
		show_list = true;
	}

    var pwidth = Ext.getBody().getViewSize().width/2;
    if(show_list) {
        pwidth = pwidth - 125;
    }
    // Left Side
    var leftpanel = Ext.create('Ext.panel.Panel', ({
//        title: 'Bacterial',
 //       layout: 'fit',
        id: 'left_side',
        html: 'Nothing loaded yet',
        autoScroll: true,
        region: 'west',
        width: pwidth,//Ext.getBody().getViewSize().width/2,
//        flex: 1
    }));


    // Right Side
    var rightpanel = Ext.create('Ext.panel.Panel', ({
//        title: 'Human',
        html: 'Nothing loaded yet',
//        layout: 'fit',
        autoScroll: true,
        id: 'right_side',
        region: 'center',
        width: pwidth,
        flex: 1
    }));

    var single_list_form = Ext.create('Ext.form.FieldContainer', ({
        defaultType: 'textfield',
//	width: '100%',
        layout: {type: 'vbox',
                 align: 'left'},

        items: [{
            fieldLabel: 'BLAST File',
            name: 'blast_file',
            value: file,
            width: '100%'
        },{
            fieldLabel: 'Query List (optional)',
            name: 'qlist',
            value: qlist,
            width: '100%'
        },{
            fieldLabel: 'Left ID suffix',
            name: 'suff1',
            value: left_suff,
            width: 200
        },{
            fieldLabel: 'Right ID suffix',
            name: 'suff2',
            value: right_suff,
            width: 200 
        }]
    }));

    var double_list_form = Ext.create('Ext.form.FieldContainer', ({
        defaultType: 'textfield',
        hidden: single_file,
        items: [{
            fieldLabel: 'Left BLAST file',
            name: 'blast1',
            value: left_file
        },{
            fieldLabel: 'Right BLAST file',
            name: 'blast2',
            value: right_file
        },{
            fieldLabel: 'Query List (optional)',
            name: 'qlist',
            value: qlist
		}]
    }));

    var type_radiogroup = Ext.create('Ext.form.RadioGroup', {
        defaultType: 'radio',
        defaults: {flex: 1},
        
        layout: 'hbox',
		// For now these will be marked hidden as it's probably 
		// better to normalize inputs with the new util scripts
		// to guarantee success in their processing instead of 
		// letting the users have too many options.
        items: [{
            boxLabel: '1 BLAST search, 2 IDs',
            inputValue: '1',
            checked: single_file,
            hidden: true, 
            name: 'num_lists',
            handler: function() {
                double_list_form.show();
                single_list_form.hide();
            }
        },{
            boxLabel: '2 BLAST searches, 1 ID',
            inputValue: '2',
            checked: !single_file,
			hidden: true,
            name: 'num_lists',
            handler: function() {
                double_list_form.hide();
                single_list_form.show();
            }
        }
		]});

	var annot_radiogroup = Ext.create('Ext.form.RadioGroup', {
		fieldLabel: 'LGT detected',
		xtype: 'radio',
		columns: 2,
		width: '100%',
		items: [
			{
			boxLabel: 'yes',
			inputValue: 'yes',
			name: 'annotation',
			id: 'radio1'
			},{
			boxLabel: 'no',
			inputValue: 'no',
			name: 'annotation',
			id: 'radio2'
			},{
			boxLabel: 'maybe',
			inputValue: 'maybe',
			name: 'annotation',
			id: 'radio3'
			},{
			boxLabel: 'custom',
			inputValue: 'custom',
			name: 'annotation',
			id: 'radio4',
				listeners: {
					render: function() {
						this.boxLabelEl.update("");
						this.field = Ext.create('Ext.form.field.Text', {
							renderTo: this.boxLabelEl,
							width: 100,
							id: 'custom_value',
							disabled: !this.getValue()
						});
						this.boxLabelEl.setStyle('display','inline-block');
					},
					change: function() {
						this.field.setDisabled(!this.getValue());
					}
				}

			},{
			xtype: 'button',
			text: 'curate',
            handler: function() {
                curatePair();
            	}  
			}]
	});

    var form = Ext.create('Ext.form.Panel', ({
//        layout: 'fit',
//        id: 'top',
        bodyPadding: 10,
        defaultType: 'textfield',
//        width: '50%',
        layout: 'hbox',
        defaults: {flex: 1},
        items: [
            {xtype: 'fieldset',
             title: 'Analyze',
             layout: 'vbox',
             defaultType: 'textfield',
             items: [
                 {fieldLabel: 'ID (prefix only)',
                  name: 'id',
                  value: id,
                  id: 'id',
                  width: 300 
                 },
				annot_radiogroup,
             ]},
            {xtype: 'fieldset',
             title: 'BLAST input',
             items: [
                 type_radiogroup,
                 single_list_form,
                 double_list_form]
           }]
    }));
    
    // Form    
    var toppanel =  Ext.create('Ext.panel.Panel', ({
		//        layout: 'fit',
        //        id: 'top',
        frame: true,
        region: 'north',
        split: true,
        collapseMode: 'header',
        collapsed: collapse_form,
        collapsible: true,
        title: 'TwinBLAST',
        defaultType: 'textfield',
        items: [form
        ],
        height: 250,
        buttonAlign: 'center',
        buttons: [{
            text: 'Reload',
            handler: function() {
                reloadPanels();
            }  
        }]
    }));

    Ext.define('links', {
        extend: 'Ext.data.Model',
        fields: [
            {name: 'name', type: 'string'},
        ]
    });
    // List
    var linkStore = Ext.create('Ext.data.Store', {
        storeId:'linkStore',
        //model: 'links',
        fields: ['name', 'annot'],
        pageSize: 500,
        proxy: {
            type: 'ajax',
            url: GUIBLAST_URL,
            actionMethods: {
                read: 'POST'
            },
            reader: {
                type: 'json',
                root: 'root'
            }
        },
        autoLoad: false,
    });
    var gridpanel = Ext.create('Ext.grid.Panel', ({
        store: linkStore,
        columns: [{header: 'link', dataIndex: 'name', flex: 1},
				  {header: 'curation note', dataIndex: 'annot', flex: 1}
			],
        region: 'east',
        forcefit: true,
        width: 250,
        title: 'Query List',
        collapsed: !show_list,
        collapsible: true,
        dockedItems: [{
            xtype: 'pagingtoolbar',
            store: linkStore,   // same store GridPanel is using
            dock: 'bottom',
            displayInfo: true
        },{
            xtype: 'button',
			text: 'download report',
			id: 'report',
            handler: function() {
                generateReport();
            	}
		}]
    }));
    // update panel body on selection change
    gridpanel.getSelectionModel().on('selectionchange', function(sm, selectedRecord) {
        if(selectedRecord.length) {
            reloadPanels({id: selectedRecord[0].data.name});
        }
    });

    function onAfterRender() {
        console.log("Here setting the history thing");
        Ext.History.on('change', function(token) {
            var starts_with = /\?/;
            console.log(token);
            if(token && starts_with.test(token) ) {
                console.log(token);
            }
        })
    }

    var vp = new Ext.Viewport({
        layout: 'border',
        autoScroll: true,
        defaults: {split: true},
        items: [toppanel,leftpanel,rightpanel,gridpanel],
        listeners: {
            afterrender: onAfterRender 
        }
    });
    
    vp.doLayout();
    
    reloadPanels({});
    
    function getUrlVars() {
        var vars = {};
        var parts = parent.location.hash.replace(/[?&]+([^=&]+)=([^&#]*)/gi,
            function(m,key,value) {
                vars[key] = value;
            });
        return vars;
    } 

    function generateReport(newvals) {
		var FILE_PATH = '/tmpblast/testing.txt';
		Ext.getCmp('report').setText('generating report, please wait...');
		Ext.getCmp('report').setDisabled(true);
        var vals = form.getValues();
        Ext.apply(vals,newvals);
		var report_config = {
            'list' : vals.blast,
            'file' : vals.blast_file,
			'qlist': vals.qlist,
			'printreport' : 1
		}
		if(vals.blast_file || vals.blast){
			Ext.Ajax.request({
				url: REPORT_URL,
				// This timeout is exceedingly high, can reduce it but if the 
				// files are huge it will take quite some time. 
				timeout: 6000000, 
				params: report_config,
            	success: function(response) {
                	var res = Ext.JSON.decode(response.responseText,true);
					if(res.success == 1) {
						// file should be ready now, re-enable that button
						Ext.getCmp('report').setText('download report');
						Ext.getCmp('report').setDisabled(false);	

						var a = document.createElement("a"); // download results
						a.href = res.path;
						a.download = "twinBLASTreport.tsv";
						a.target = "_blank";
						document.body.appendChild(a);
						a.click();
						document.body.removeChild(a); // clean up
						delete a;
					}
				}
			});
		}
    } 

    function curatePair() {
		var seq_id = Ext.ComponentQuery.query('#id')[0].getValue();
		var annot_note = form.getForm().getValues()['annotation'];
		if(annot_note == 'custom'){
			annot_note = Ext.ComponentQuery.query('#custom_value')[0].getValue();
		}
		var annot_config = {
			'seq_id': seq_id,
			'annot_note': annot_note
		}
		// Simple check to ensure that this only proceeds if ID is defined
		if(seq_id){
			Ext.Ajax.request({
				url: CURATION_URL,
				params: annot_config
			});
			linkStore.load();
		}
    } 

    function reloadPanels(newvals) {
        var vals = form.getValues();
        Ext.apply(vals,newvals);
        if(vals.num_lists== "1" && (vals.blast || vals.blast_file)){ //&& vals.id) {
            var newconfig = {
                'leftsuff' : vals.suff1,
                'rightsuff' : vals.suff2,
                'list' : vals.blast,
                'file' : vals.blast_file,
				'qlist': vals.qlist
            };
            
            // Load each panel
            if(vals.id) {
                newconfig['id'] = vals.id + vals.suff1;
                reloadPanel(newconfig,leftpanel);
                newconfig['id'] = vals.id + vals.suff2;
                reloadPanel(newconfig,rightpanel);
                form.getForm().setValues([{'id': 'id', value: vals.id}]);
            }
            if((vals.id && linkStore.getCount() == 0) || !vals.id) {
            newconfig['printlist'] = 1;
            if(vals.qlist) {
                newconfig.qlist = vals.qlist;
            }
            linkStore.proxy.extraParams = newconfig;
            linkStore.load({callback: function(records,operation,success) {
                if(!records || (records && records.length == 0)) {
                    if(operation.response) {
                    var res = Ext.JSON.decode(operation.response.responseText);
                    if(res.message) {
                        vp.setLoading(res.message);
                        newconfig['printlist'] = 0;
                        checkStatusTask.args = [newconfig];
                        checkStatusTask.start(); 
                    }}
                    gridpanel.doLayout();
                }
                if(!success) {
                }
            }});
            }
            
            // Set the URL
            setUrlVars({
                'leftsuff' : vals.suff1,
                'rightsuff' : vals.suff2,
                'id': vals.id,
                'file' : vals.blast_file,
                'list' : vals.blast,
                'qlist': vals.qlist
            });
        
        }else if(vals.num_lists == "2" && vals.blast1 && vals.blast2 && vals.id) {
        
            var config = {
                'list' : vals.blast1,
                'id' : vals.id
            };
            
            // Load each panel
            reloadPanel(config,leftpanel);
            config['list'] = vals.blast2;
            reloadPanel(config,rightpanel);
            if(!vals.id) {
            }
            // Set the URL            
            setUrlVars({
                'leftfile' : vals.blast1,
                'rightfile' : vals.blast2,
                'id': vals.id,
                'qlist' : vals.qlist
            });
        
        }
    
    }
    function checkStatus(config) {
        Ext.Ajax.request({
            url: GUIBLAST_URL,
            params: config,
			timeout: 120000, 
            success: function(response) {
                var res = Ext.JSON.decode(response.responseText,true);
                if(res) {
                    vp.setLoading(res.message);
                    setPanelsLoading(false);
                }
                else {
                    checkStatusTask.stop();
                    vp.setLoading(false);
                    reloadPanels({});
                }
            },
            failure: function(response) {
                  vp.setLoading('Hmmm... I appear to be having trouble somewhere. Try refresh or wait a little longer and it might come back.');
                  setPanelsLoading(false);
            }
        });            
    }

    function reloadPanel(config,panel) {
        if(panel.isVisible()) {
            panel.setLoading({msg: 'Patience my friend...'});
        }
        Ext.Ajax.request({
            url: GUIBLAST_URL,
            params: config,
			timeout: 120000, 
            success: function(response) {
                var res = Ext.JSON.decode(response.responseText,true);
                if((!config.printlist && res) || (res && config.printlist && !res.total)) {
                    panel.setLoading(false);
                    vp.setLoading(res.message);
                    setPanelsLoading(false);
                    checkStatusTask.args = [config];
                    checkStatusTask.start();
                }
                else {
                        panel.update(response.responseText);
                    vp.setLoading(false);
                    panel.setLoading(false);
                }
            },
            failure: function(response) {
                panel.setLoading(false);
                vp.setLoading('Hmmm... I appear to be having trouble somewhere. Just wait a second and it might come back.');
                setPanelsLoading(false);
            }
        }); 
    }
    function setPanelsLoading(message) {
        gridpanel.setLoading(message);
        leftpanel.setLoading(message);
        rightpanel.setLoading(message);
    } 
    function setForm(obj) {
        

    }
    function setUrlVars(obj) {
        var url = Ext.urlEncode(obj);
        parent.location.hash = '?'+url;
    }
});
