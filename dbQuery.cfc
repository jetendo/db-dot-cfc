<cfcomponent>
	<cffunction name="init" access="package" output="no">
    	<cfargument name="dbObject" type="component" required="yes">
    	<cfargument name="config" type="struct" required="no">
        <cfscript>
		variables.config=arguments.dbObject.getConfig();
		arguments.config.dbQuery=this;
		variables.db=arguments.dbObject;
		if(structkeyexists(arguments, 'config')){
			structappend(variables.config, arguments.config, true);
			if(structkeyexists(arguments.config, 'parseSQLFunctionStruct')){
				variables.config.parseSQLFunctionStruct=duplicate(arguments.config.parseSQLFunctionStruct);
			}
		}
		variables.tableSQLString=":ztablesql:";
		variables.trustSQLString=":ztrustedsql:";
		variables.config.arrParam=[];
		</cfscript>
    </cffunction>
    
    
	<cffunction name="getConfig" access="public" output="no" hint="Returns a COPY of the config data for debugging purposes.">
    	<cfscript>
		return duplicate(variables.config);
		</cfscript>
    </cffunction>
    
	<cffunction name="param" access="public" returntype="string" output="no">
    	<cfargument name="value" type="string" required="yes">
    	<cfargument name="cfsqltype" type="string" required="no">
        <cfscript>
		if(structkeyexists(arguments, 'cfsqltype')){
			arrayappend(variables.config.arrParam, {value:arguments.value, cfsqltype:arguments.cfsqltype});
		}else{
			if(isnumeric(arguments.value)){
				if(find(".", arguments.value)){
					arrayappend(variables.config.arrParam, {value:arguments.value, cfsqltype:'cf_sql_decimal'});
				}else{
					arrayappend(variables.config.arrParam, {value:arguments.value, cfsqltype:'cf_sql_bigint'});
				}
			}else{
				arrayappend(variables.config.arrParam, {value:arguments.value});
			}
		}
		return "?";
		</cfscript>
	</cffunction>
    
	<cffunction name="table" access="public" returntype="string" output="no">
    	<cfargument name="name" type="string" required="yes">
    	<cfargument name="datasource" type="string" required="no" default="#variables.config.datasource#">
        <cfscript>
		var zt="";
		if(variables.config.verifyQueriesEnabled){
			zt=variables.tableSQLString;
		}
		if(len(arguments.datasource)){
			variables.config.datasource=arguments.datasource;
			return variables.config.identifierQuoteCharacter&arguments.datasource&variables.config.identifierQuoteCharacter&"."&variables.config.identifierQuoteCharacter&zt&variables.config.tablePrefix&arguments.name&variables.config.identifierQuoteCharacter;
		}else{
			return variables.config.identifierQuoteCharacter&zt&variables.config.tablePrefix&arguments.name&variables.config.identifierQuoteCharacter;
		}
		</cfscript>
	</cffunction>
    
	<cffunction name="trustedSQL" access="public" returntype="string" output="no">
    	<cfargument name="value" type="string" required="yes">
        <cfscript>
		if(variables.config.verifyQueriesEnabled){
			return variables.trustSQLString&arguments.value&variables.trustSQLString;
		}else{
			return arguments.value;
		}
		</cfscript>
	</cffunction>
    
    <cffunction name="execute" access="public" returntype="any" output="no" hint="Use for any query.">
    	<cfargument name="name" type="variablename" required="yes" hint="A variable name for the query result.  Helps to identify query when debugging.">
        <cfscript>
		variables.config.sql=this.sql;
		var executeResult=variables.db.execute(arguments.name, variables.config);
		this.reset();
		return executeResult.result;
		</cfscript>
    </cffunction>
    
    <cffunction name="insert" access="public" returntype="any" output="no" hint="Use for insert statements to auto-retrieve the inserted id more easily.">
    	<cfargument name="name" type="variablename" required="yes" hint="A variable name for the query result.  Helps to identify query when debugging.">
        <cfscript>
		variables.config.sql=this.sql;
		var executeResult=variables.db.insertAndReturnId(arguments.name, variables.config);
		this.reset();
		return executeResult.result;
		</cfscript>
    </cffunction>
    
	<cffunction name="reset" access="public" returntype="any" output="no">
    	<cfscript>
		var c=0;
		if(variables.config.autoReset){
			c=variables.db.getConfig();
        	structappend(variables.config, c, true);
			variables.config.parseSQLFunctionStruct=duplicate(c.parseSQLFunctionStruct);
		}
		variables.config.arrParam=[];
		</cfscript>
    </cffunction>
</cfcomponent>