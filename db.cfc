<!--- 
db.cfc
Version: 0.1.000

Project Home Page: https://www.jetendo.com/manual/view/current/2.1/db-dot-cfc.html
Github Home Page: https://github.com/jetendo/db-dot-cfc

Licensed under the MIT license
http://www.opensource.org/licenses/mit-license.php
Copyright (c) 2013 Far Beyond Code LLC.
 --->
<cfcomponent output="no" name="db.cfc" hint="Enhances cfquery by analyzing SQL to enforce security & framework conventions.">
	<cfoutput>
    <cffunction name="init" access="public" output="no">
    	<cfargument name="ts" type="struct" required="no" default="#structnew()#">
		<cfscript>
		this.config={
			identifierQuoteCharacter:'`', // Modify the character that should surround database, table or field names.
			dbtype:'datasource', // query, hsql or datasource are valid values.
			datasource:false, // Optional change the datasource.  This option is required if the query doesn't use db.table().
			enableTablePrefixing:true, // This allows a table that is usually named "user", to be prefixed so that it is automatically verified/modified to be "prefix_user" when using this component
			autoReset:true, // Set to false to allow the current db object to retain it's configuration after running db.execute().  Only the parameters will be cleared.
			lazy:false, // Railo's lazy="true" option returns a simple Java resultset instead of the ColdFusion compatible query object.  This reduces memory usage when some of the columns are unused.
			disableQueryLog:false, // Set to true to disable query logging.
			cachedWithin:false, // optionally set to a timespan to enable query caching
			arrQueryLog:[], // Assign a query log to this object.  In Railo, the query log can be shared since arrays are assigned by reference.
			tablePrefix:"", // Set a table prefix string to be prepend to all table names.
			sql:"", // specify the full sql statement
			verifyQueriesEnabled:false, // Enabling sql verification takes more cpu time, so it should only run when testing in development.
			parseSQLFunctionStruct:{} // Each struct key value should be a function that accepts and returns parsedSQLStruct. Prototype: struct customFunction(required struct parsedSQLStruct, required string defaultDatabaseName);
		};
		structappend(this.config, ts, true);
        structappend(this, this.config, true);
		
		// internal variables:
		variables.tableSQLString=":ztablesql:";
		variables.trustSQLString=":ztrustedsql:";
		variables.arrParam=[];
		variables.lastSQL="";
		return this;
        </cfscript>
    </cffunction>
    
    <cffunction name="reset" access="public" output="no">
    	<cfscript>
        structappend(this, this.config, true);
		variables.arrParam=[];
		</cfscript>
    </cffunction>
    
	<cffunction name="table" access="public" returntype="string" output="no">
    	<cfargument name="name" type="string" required="yes">
    	<cfargument name="datasource" type="string" required="no" default="#this.datasource#">
        <cfscript>
		var zt="";
		if(this.verifyQueriesEnabled){
			zt=variables.tableSQLString;
		}
		if(len(arguments.datasource)){
			this.datasource=arguments.datasource;
			return this.identifierQuoteCharacter&arguments.datasource&this.identifierQuoteCharacter&"."&this.identifierQuoteCharacter&zt&this.tablePrefix&arguments.name&this.identifierQuoteCharacter;
		}else{
			return this.identifierQuoteCharacter&zt&this.tablePrefix&arguments.name&this.identifierQuoteCharacter;
		}
		</cfscript>
	</cffunction>
    
	<cffunction name="param" access="public" returntype="string" output="no">
    	<cfargument name="value" type="string" required="yes">
    	<cfargument name="cfsqltype" type="string" required="no">
        <cfscript>
		if(structkeyexists(arguments, 'cfsqltype')){
			arrayappend(variables.arrParam, {value:arguments.value, cfsqltype:arguments.cfsqltype});
		}else{
			if(isnumeric(arguments.value)){
				if(find(".", arguments.value)){
					arrayappend(variables.arrParam, {value:arguments.value, cfsqltype:'cf_sql_decimal'});
				}else{
					arrayappend(variables.arrParam, {value:arguments.value, cfsqltype:'cf_sql_bigint'});
				}
			}else{
				arrayappend(variables.arrParam, {value:arguments.value});
			}
		}
		return "?";
		</cfscript>
	</cffunction>
    
    <cffunction name="execute" returntype="any" output="no">
    	<cfargument name="name" type="variablename" required="yes" hint="A variable name for the resulting query object.  Helps to identify query when debugging.">
        <cfscript>
        var queryStruct={
			lazy=this.lazy,
			datasource=this.datasource	
		};
        var pos=0;
		var processedSQL="";
        var startIndex=1;
        var curArg=1;
        var running=true;
        var db=structnew();
        var cfquery=0;
		var k=0;
		var i=0;
		var s=0;
		var paramCount=arraylen(variables.arrParam);
		if(this.dbtype NEQ ""){
			queryStruct.dbtype=this.dbtype;	
			structdelete(queryStruct, 'datasource');
		}else if(isBoolean(queryStruct.datasource)){
			this.throwError("db.datasource must be set before running db.execute() by either using db.table() or db.datasource=""myDatasource"";");
		}
		if(not isBoolean(this.cachedWithin)){
			queryStruct.cachedWithin=this.cachedWithin;	
		}
        queryStruct.name="db."&arguments.name;
		if(len(this.sql) EQ 0){
			this.throwError("The sql statement must be set before running db.execute();");
		}
		if(this.verifyQueriesEnabled){
			if(compare(this.sql, variables.lastSQL) NEQ 0){
				variables.lastSQL=this.sql;
				variables.verifySQLParamsAreSecure(this.sql);
				processedSQL=replacenocase(this.sql,variables.trustSQLString,"","all");
				processedSQL=variables.parseSQL(processedSQL, this.datasource);
			}else{
				processedSQL=replacenocase(replacenocase(this.sql,variables.trustSQLString,"","all"), variables.tableSQLString, "","all");
			}
		}else{
			processedSQL=this.sql;
		}
        if(this.disableQueryLog EQ false){
            ArrayAppend(this.arrQueryLog, processedSQL);
        }
        </cfscript>
        <cftry>
            <cfif paramCount>
                <cfquery attributeCollection="#queryStruct#"><cfloop condition="#running#"><cfscript>
                    pos=find("?", processedSQL, startIndex);
                    </cfscript><cfif pos EQ 0><cfset running=false><cfelse><cfset s=mid(processedSQL, startIndex, pos-startIndex)>#preserveSingleQuotes(s)#<cfqueryparam attributeCollection="#variables.arrParam[curArg]#"><cfscript>
                    startIndex=pos+1;
                    curArg++;
                    </cfscript></cfif></cfloop><cfscript>
					if(paramCount GT curArg-1){ 
						this.throwError("db.execute failed: There were more parameters then question marks in the current sql statement.  You must run db.execute() before building any additional sql statements with the same db object.  If you need to build multiple queries before running execute, you must use a copy of db, such as db2=duplicate(db);<br /><br />SQL Statement:<br />"&processedSQL); 
					}
					s=mid(processedSQL, startIndex, len(processedSQL)-(startIndex-1));
                    </cfscript>#preserveSingleQuotes(s)#</cfquery>
            <cfelse>
                <cfquery attributeCollection="#queryStruct#">#preserveSingleQuotes(processedSQL)#</cfquery>
            </cfif>
            <cfcatch type="database">
            	<cfscript>
				if(this.autoReset){
					structappend(this, this.config, true);
				}
				variables.arrParam=[]; // has to be created separately to ensure it is a separate object
				</cfscript>
                <cfif left(trim(processedSQL), 7) NEQ "INSERT "><cfrethrow></cfif>
                <cfscript>
                if(this.disableQueryLog EQ false){
                    ArrayAppend(this.arrQueryLog, "Query ##"& ArrayLen(this.arrQueryLog)&" failed to execute for datasource, "&this.datasource&".<br />CFcatch.message: "&CFcatch.message&"<br />cfcatch.detail: "&cfcatch.detail);
                }
                </cfscript>
                <!--- return false when INSERT fails, because we assume this is a duplicate key error. --->
                <cfreturn false>
            </cfcatch>
            <cfcatch type="any"><cfscript>
				if(paramCount and curArg GT paramCount){
					this.throwError("db.execute failed: There were more question marks then parameters in the current sql statement.  You must use db.param() to specify parameters.  A literal question mark is not allowed.<br /><br />SQL Statement:<br />"&processedSQL);
				}
				</cfscript><cfrethrow></cfcatch>
        </cftry>
		<cfscript>
		if(this.autoReset){
        	structappend(this, this.config, true);
		}
		variables.arrParam=[]; // has to be created separately to ensure it is a separate object
        </cfscript>
        <cfif structkeyexists(db, arguments.name)>
            <cfreturn db[arguments.name]>
        <cfelse>
            <cfreturn true>
        </cfif>
    </cffunction>
    
	<cffunction name="trustedSQL" access="public" returntype="string" output="no">
    	<cfargument name="value" type="string" required="yes">
        <cfscript>
		if(this.verifyQueriesEnabled){
			return variables.trustSQLString&arguments.value&variables.trustSQLString;
		}else{
			return arguments.value;
		}
		</cfscript>
	</cffunction>
    
    <cffunction name="getCleanSQL" access="private" output="no" returntype="string">
        <cfargument name="sql" type="string" required="yes">
        <cfscript>
		return replace(replace(arguments.sql, variables.trustSQLString, "", "all"), variables.tableSQLString, "", "all");
		</cfscript>
    </cffunction>
    
    <cffunction name="verifySQLParamsAreSecure" access="private" output="no" returntype="any">
        <cfargument name="sql" type="string" required="yes">
        <cfscript>
        var s=arguments.sql;
        var a=0;
        var i=0;
        var k=0;
		// strip trusted sql
        s=rereplace(s, variables.trustSQLString&".*?"&variables.trustSQLString, chr(9), "all");
		
		// detect string literals
        if(find("'", s) NEQ 0 or find('"', s) NEQ 0){
            this.throwError("The SQL statement can't contain single or double quoted string literals when using the db component.  You must use db.param() to specify all values including constants.<br /><br />SQL Statement:<br />"&variables.getCleanSQL(arguments.sql));	
        }
		// strip c style comments
        s=replace(s, chr(10), " ", "all");
        s=replace(s, chr(13), " ", "all");
        s=replace(s, chr(9), " ", "all");
        s=replace(s, "/*", chr(10), "all");
        s=replace(s, "*/", chr(13), "all");
        s=replace(s, "*", chr(9), "all");
        s=rereplace(s, chr(10)&"[^\*]*?"&chr(13), chr(9), "all");
		
		// strip table/db/field names
		if(this.identifierQuoteCharacter NEQ "" and this.identifierQuoteCharacter NEQ "'"){
        	s=rereplace(s, this.identifierQuoteCharacter&"[^"&this.identifierQuoteCharacter&"]*"&this.identifierQuoteCharacter, chr(9), "all");
		}
		
		// strip words not beginning with a number
        s=rereplace(s, "[a-zA-Z_][a-zA-Z\._0-9]*", chr(9), "all");
        
		// detect any remaining numbers
		if(refind("[0-9]", s) NEQ 0){
			this.throwError("The SQL statement can't contain literal numbers when using the db component.  You must use db.param() to specify all values including constants.<br /><br />SQL Statement:<br />"&variables.getCleanSQL(arguments.sql)); 	
        }
        return s;
        </cfscript> 
    </cffunction>
    
    <cffunction name="parseSQL" access="private" output="no" returntype="any">
        <cfargument name="sqlString" type="string" required="yes">
        <cfargument name="defaultDatabaseName" type="string" required="yes">
        <cfscript>
        var local=structnew();
        var c=arguments.sqlString;
		local.ps=structnew();
        local.ps.arrError=arraynew(1);
        local.ps.arrTable=arraynew(1);
        local.c=replace(replace(replace(replace(replace(local.c,chr(10)," ","all"),chr(9)," ","all"),chr(13)," ","all"),")"," ) ","all"),"("," ( ","all");
        local.c=" "&rereplace(replace(replace(replace(lcase(local.c),"\\"," ","all"),"\'"," ","all"),'\"'," ","all"), "/\*.*?\*/"," ", "all")&" ";
        local.c=rereplace(local.c,"'[^']*?'","''","all");
        local.c=rereplace(local.c,'"[^"]*?"',"''","all");
        
        local.ps.wherePos=findnocase(" where ",local.c);
        local.ps.setPos=findnocase(" set ",local.c);
        local.ps.valuesPos=refindnocase("\)\s*values",local.c);
        local.ps.fromPos=findnocase(" from ",local.c);
        local.ps.selectPos=findnocase(" select ",local.c);
        local.ps.insertPos=findnocase(" insert ",local.c);
        local.ps.replacePos=findnocase(" replace ",local.c);
        local.ps.intoPos=findnocase(" into ",local.c);
        local.ps.limitPos=findnocase(" limit ",local.c);
        local.ps.groupByPos=findnocase(" group by ",local.c);
        local.ps.orderByPos=findnocase(" order by ",local.c);
        local.ps.havingPos=findnocase(" having ",local.c);
        local.ps.firstLeftJoinPos=findnocase(" left join ",local.c);
        local.ps.firstParenthesisPos=findnocase(" ( ",local.c);
        local.ps.firstWHEREPos=len(local.c);
        if(left(trim(local.c), 5) EQ "show "){
            if(local.ps.fromPos EQ 0){
                return arguments.sqlString;
            }
        }
        if(local.ps.wherePos){
            local.ps.firstWHEREPos=local.ps.wherePos;
        }else if(local.ps.groupByPos){
            local.ps.firstWHEREPos=local.ps.groupByPos;
        }else if(local.ps.orderByPos){
            local.ps.firstWHEREPos=local.ps.orderByPos;
        }else if(local.ps.orderByPos){
            local.ps.firstWHEREPos=local.ps.orderByPos;
        }else if(local.ps.havingPos){
            local.ps.firstWHEREPos=local.ps.havingPos;
        }else if(local.ps.limitPos){
            local.ps.firstWHEREPos=local.ps.limitPos;
        }
        local.ps.lastWHEREPos=len(local.c);
        if(local.ps.groupByPos){
            local.ps.lastWHEREPos=local.ps.groupByPos;
        }else if(local.ps.orderByPos){
            local.ps.lastWHEREPos=local.ps.orderByPos;
        }else if(local.ps.havingPos){
            local.ps.lastWHEREPos=local.ps.havingPos;
        }else if(local.ps.limitPos){
            local.ps.lastWHEREPos=local.ps.limitPos;
        }
        local.ps.setStatement="";
        if(local.ps.setPos){
            if(local.ps.wherePos){
                local.ps.setStatement=mid(local.c, local.ps.setPos+5, local.ps.wherePos-(local.ps.setPos+5));
            }else{
                local.ps.setStatement=mid(local.c, local.ps.setPos+5, len(local.c)-(local.ps.setPos+5));
            }
        }
        if(local.ps.wherePos){
            local.ps.whereStatement=mid(local.c, local.ps.wherePos+6, local.ps.lastWHEREPos-(local.ps.wherePos+6));
        }else{
            local.ps.whereStatement="";
        }
        local.ps.arrLeftJoin=arraynew(1);
        local.matching=true;
        local.curPos=1;
        while(local.matching){
            local.t9=structnew();
            local.t9.leftJoinPos=findnocase(" left join ",local.c, local.curPos);
            if(local.t9.leftJoinPos EQ 0) break;
            local.t9.onPos=findnocase(" on ",local.c, local.t9.leftJoinPos+1);
            if(local.t9.onPos EQ 0 or local.t9.onPos GT local.ps.firstWHEREPos){
                local.t9.onPos=local.ps.firstWHEREPos;
            }
            local.t9.table=mid(local.c, local.t9.leftJoinPos+11, local.t9.onPos-(local.t9.leftJoinPos+11))
			if(this.identifierQuoteCharacter NEQ ""){
				local.t9.table=trim(replace(local.t9.table, this.identifierQuoteCharacter,"","all"));
			}
            if(local.t9.table CONTAINS " as "){
                local.pos=findnocase(" as ",local.t9.table);
                local.t9.tableAlias=trim(mid(local.t9.table, local.pos+4, len(local.t9.table)-(local.pos+3)));
                local.t9.table=trim(left(local.t9.table,local.pos-1));
            }else if(local.t9.table CONTAINS " "){
                local.pos=findnocase(" ",local.t9.table);
                local.t9.tableAlias=trim(mid(local.t9.table, local.pos+1, len(local.t9.table)-(local.pos)));
                local.t9.table=trim(left(local.t9.table,local.pos-1));
            }else{
                local.t9.table=trim(local.t9.table);
                local.t9.tableAlias=trim(local.t9.table);
            }
			if(this.enableTablePrefixing){
				if(findnocase(variables.tableSQLString,local.t9.table) EQ 0){
					arrayappend(local.ps.arrError, "All tables in queries must be generated with db.table(table, datasource); function. This table wasn't: "&local.t9.table);
				}else{
					local.t9.table=replacenocase(local.t9.table,variables.tableSQLString,"");	
				}
			}
            local.t9.onstatement="";
            if(local.t9.table DOES NOT CONTAIN "."){
                local.t9.table=arguments.defaultDatabaseName&"."&local.t9.table;
            }else{
                if(local.t9.tableAlias CONTAINS "."){
                    local.t9.tableAlias=trim(listgetat(local.t9.tableAlias,2,"."));
                }
            }
            local.curPos=local.t9.onPos+1;
            arrayappend(local.ps.arrLeftJoin, local.t9);
        }
		
		
        
        if(local.ps.firstLeftJoinPos){
            local.ps.endOfFromPos=local.ps.firstLeftJoinPos;
        }else if(local.ps.firstWHEREPos){
            local.ps.endOfFromPos=local.ps.firstWHEREPos;
        }else{
            local.ps.endOfFromPos=len(local.c);
        }
        
        if(local.ps.intoPos and (local.ps.selectPos EQ 0 or local.ps.selectPos GT local.ps.intoPos)){
            if(local.ps.setPos){
                local.t9=structnew();
                local.t9.type="into";
                local.t9.table=mid(local.c, local.ps.intoPos+5, local.ps.setPos-(local.ps.intoPos+5));
                local.t9.tableAlias=local.t9.table;
                arrayappend(local.ps.arrTable, local.t9);
            }else if(local.ps.firstParenthesisPos){
                local.t9=structnew();
                local.t9.type="into";
                local.t9.table=mid(local.c, local.ps.intoPos+5, local.ps.firstParenthesisPos-(local.ps.intoPos+5));
                local.t9.tableAlias=local.t9.table;
                arrayappend(local.ps.arrTable, local.t9);
            }else{
                if(local.ps.selectPos){
                    local.t9=structnew();
                    local.t9.type="into";
                    local.t9.table=mid(local.c, local.ps.intoPos+5, local.ps.selectPos-(local.ps.intoPos+5));
                    local.t9.tableAlias=local.t9.table;
                    arrayappend(local.ps.arrTable, local.t9);
                }
            }
        }
        if(local.ps.fromPos){
            
            local.c2=mid(local.c, local.ps.fromPos+5, local.ps.endOfFromPos-(local.ps.fromPos+5));
            
            local.c2=replacenocase(replacenocase(replacenocase(replacenocase(replace(replace(local.c2,")"," ","all"),"("," ","all"), " STRAIGHT_JOIN ", " , ","all"), " CROSS JOIN ", " , ","all"), " INNER JOIN ", " , ","all"), " JOIN ", " , ","all");
            local.arrT2=listtoarray(local.c2, ",");
            for(local.i2=1;local.i2 LTE arraylen(local.arrT2);local.i2++){
                local.arrT2[local.i2]=trim(local.arrT2[local.i2]);
                local.t9=structnew();
                local.t9.type="from";
                if(local.arrT2[local.i2] CONTAINS " as "){
                    local.pos=findnocase(" as ", local.arrT2[local.i2]);
                    local.t9.tableAlias=trim(mid(local.arrT2[local.i2], local.pos+4, len(local.arrT2[local.i2])-(local.pos+3)));
                    local.t9.table=trim(left(local.arrT2[local.i2],local.pos-1));
                }else if(local.arrT2[local.i2] CONTAINS " "){
                    local.pos=findnocase(" ", local.arrT2[local.i2]);
                    local.t9.tableAlias=trim(mid(local.arrT2[local.i2], local.pos+1, len(local.arrT2[local.i2])-(local.pos)));
                    local.t9.table=trim(left(local.arrT2[local.i2],local.pos-1));
                }else{
                    local.t9.table=trim(local.arrT2[local.i2]);
                    local.t9.tableAlias=trim(local.arrT2[local.i2]);
                }
				if(this.enableTablePrefixing){
					if(findnocase(variables.tableSQLString,local.t9.table) EQ 0){
						arrayappend(local.ps.arrError, "All tables in queries must be generated with db.table(table, datasource); function. This table wasn't: "&local.t9.table);
					}else{
						local.t9.table=replacenocase(local.t9.table,variables.tableSQLString,this.identifierQuoteCharacter);	
					}
				}
                arrayappend(local.ps.arrTable, local.t9);
            }
        }
		
		
        for(local.i2=1;local.i2 LTE arraylen(local.ps.arrLeftJoin);local.i2++){
            if(local.i2 EQ arraylen(local.ps.arrLeftJoin)){
                local.np=local.ps.firstWHEREPos;
            }else{
                local.np=local.ps.arrLeftJoin[local.i2+1].leftJoinPos;
            }
            if(local.np NEQ local.ps.arrLeftJoin[local.i2].onPos){
                local.ps.arrLeftJoin[local.i2].onstatement=mid(local.c, local.ps.arrLeftJoin[local.i2].onPos+4, local.np-(local.ps.arrLeftJoin[local.i2].onPos+4));
            }
        }
        for(local.i2=1;local.i2 LTE arraylen(local.ps.arrTable);local.i2++){
			if(this.identifierQuoteCharacter NEQ ""){
				local.ps.arrTable[local.i2].table=trim(replace(local.ps.arrTable[local.i2].table,this.identifierQuoteCharacter,"","all"));
				local.ps.arrTable[local.i2].tableAlias=trim(replace(local.ps.arrTable[local.i2].tableAlias,this.identifierQuoteCharacter,"","all"));
			}
            if(local.ps.arrTable[local.i2].table DOES NOT CONTAIN "."){
                local.ps.arrTable[local.i2].table=arguments.defaultDatabaseName&"."&local.ps.arrTable[local.i2].table;
            }else{
                if(local.ps.arrTable[local.i2].tableAlias CONTAINS "."){
                    local.ps.arrTable[local.i2].tableAlias=trim(listgetat(local.ps.arrTable[local.i2].tableAlias,2,"."));
                }
            }
        }
		local.ps.defaultDatabaseName=arguments.defaultDatabaseName;
        local.ps.sql=replace(arguments.sqlString, variables.tableSQLString,"","all");
		for(local.i2 in this.parseSQLFunctionStruct){
			local.s=this.parseSQLFunctionStruct[local.i2];
			local.ps=local.s(local.ps);
		}
        if(arraylen(local.ps.arrError) NEQ 0){
			this.throwError(arraytolist(local.ps.arrError, "<br />")&"<br /><br />SQL Statement<br />"&local.ps.sql);
        }
        return local.ps.sql;
        </cfscript>
    </cffunction> 
    
    <cffunction name="throwError" access="private" output="yes">
    	<cfargument name="message" type="string" required="yes">
    	<cfscript>
        throw("An error occured with a query that was built just prior to calling db.execute().<br />"&arguments.message, "custom");
		</cfscript>
    </cffunction>
    
    
    </cfoutput>
</cfcomponent>