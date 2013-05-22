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
		variables.config={
			insertIdSQL:"select last_insert_id() id", // the select statement required to retrieve the ID just inserted by an insert query.  Automatically executed when using db.insert()
			identifierQuoteCharacter:'`', // Modify the character that should surround database, table or field names.
			dbtype:'datasource', // query, hsql or datasource are valid values.
			datasource:false, // Optional change the datasource.  This option is required if the query doesn't use dbQuery.table().
			enableTablePrefixing:true, // This allows a table that is usually named "user", to be prefixed so that it is automatically verified/modified to be "prefix_user" when using this component
			autoReset:true, // Set to false to allow the current db object to retain it's configuration after running db.execute().  Only the parameters will be cleared.
			lazy:false, // Railo's lazy="true" option returns a simple Java resultset instead of the ColdFusion compatible query result.  This reduces memory usage when some of the columns are unused.
			disableQueryLog:false, // Set to true to disable query logging.
			cacheForSeconds:0, // optionally set to a number of seconds to enable query caching
			arrQueryLog:[], // Assign a query log to this object.  In Railo, the query log can be shared since arrays are assigned by reference.
			tablePrefix:"", // Set a table prefix string to be prepend to all table names.
			sql:"", // specify the full sql statement
			verifyQueriesEnabled:false, // Enabling sql verification takes more cpu time, so it should only run when testing in development.
			parseSQLFunctionStruct:{}, // Each struct key value should be a function that accepts and returns parsedSQLStruct. Prototype: struct customFunction(required struct parsedSQLStruct, required string defaultDatabaseName);
			cacheStruct:{}, // Set to an application or server scope struct to store this data in shared memory. Use structnew('soft') on railo to have automatic garbage collection when the JVM is low on memory.
			cacheEnabled: true // Set to false to disable the query cache
		};
		structappend(variables.config, arguments.ts, true);
		if(structkeyexists(arguments.ts, 'parseSQLFunctionStruct')){
			variables.config.parseSQLFunctionStruct=arguments.ts.parseSQLFunctionStruct;
		}
		variables.cacheStruct=variables.config.cacheStruct;
		structdelete(variables.config, 'cacheStruct');
		variables.tableSQLString=":ztablesql:";
		variables.trustSQLString=":ztrustedsql:";
		variables.lastSQL="";
		variables.cachedQueryObject=createobject("dbQuery");
		return this;
        </cfscript>
    </cffunction>
    
    <cffunction name="getConfig" access="package" output="no" returntype="struct">
    	<cfscript>
		return variables.config;
		</cfscript>
    </cffunction>
    
    <cffunction name="processSQL" access="private" output="no" returntype="string">
    	<cfargument name="configStruct" type="struct" required="yes">
        <cfscript>
		var processedSQL=0;
		if(arguments.configStruct.verifyQueriesEnabled){
			if(compare(arguments.configStruct.sql, variables.lastSQL) NEQ 0){
				variables.lastSQL=arguments.configStruct.sql;
				variables.verifySQLParamsAreSecure(arguments.configStruct);
				processedSQL=replacenocase(arguments.configStruct.sql,variables.trustSQLString,"","all");
				processedSQL=trim(variables.parseSQL(arguments.configStruct, processedSQL, arguments.configStruct.datasource));
			}else{
				processedSQL=trim(replacenocase(replacenocase(arguments.configStruct.sql,variables.trustSQLString,"","all"), variables.tableSQLString, "","all"));
			}
		}else{
			processedSQL=trim(arguments.configStruct.sql);
		}
        if(arguments.configStruct.disableQueryLog EQ false){
            ArrayAppend(arguments.configStruct.arrQueryLog, processedSQL);
        }
		return processedSQL;
		</cfscript>
    </cffunction>
    
    
    <cffunction name="checkQueryCache" access="private" output="no" returntype="struct">
    	<cfargument name="configStruct" type="struct" required="yes">
    	<cfargument name="sql" type="string" required="yes">
    	<cfargument name="nowDate" type="date" required="yes">
        <cfscript>
		var arrOption=[];
		var paramIndex=0;
		var paramKey=0;
		var hashCode=0;
		var currentParamStruct=arguments.configStruct.arrParam;
		var paramCount=arraylen(currentParamStruct);
		arrayappend(arrOption, "dbtype="&arguments.configStruct.dbtype&chr(10)&"datasource="&arguments.configStruct.datasource&chr(10)&"lazy="&arguments.configStruct.lazy&chr(10)&"cacheForSeconds="&arguments.configStruct.cacheForSeconds&chr(10)&"tablePrefix="&arguments.configStruct.tablePrefix&chr(10)&"sql="&arguments.sql&chr(10));
		for(paramIndex=1;paramIndex LTE paramCount;paramIndex++){
			for(paramKey in currentParamStruct[paramIndex]){
				arrayAppend(arrOption, paramKey&"="&currentParamStruct[paramIndex][paramKey]&chr(10));
			}
		}
		hashCode=hash(arraytolist(arrOption,""),"sha-256");
		if(structkeyexists(variables.cacheStruct, hashCode)){
			if(datediff("s", variables.cacheStruct[hashCode].date, arguments.nowDate) LT arguments.configStruct.cacheForSeconds){
				arguments.configStruct.dbQuery.reset();
				return { success:true, hashCode:hashCode, result:variables.cacheStruct[hashCode].result };
			}else{
				structdelete(variables.cacheStruct, hashCode);
			}
		}
		return {success:false, hashCode:hashCode};
		</cfscript>
    </cffunction>
    
    
    <cffunction name="runQuery" access="private" returntype="any" output="no">
    	<cfargument name="configStruct" type="struct" required="yes">
    	<cfargument name="name" type="variablename" required="yes" hint="A variable name for the query result.  Helps to identify query when debugging.">
    	<cfargument name="sql" type="string" required="yes">
    	<cfscript>
		var running=true;
        var queryStruct={
			lazy=arguments.configStruct.lazy,
			datasource=arguments.configStruct.datasource	
		};
        var cfquery=0;
        var db=structnew();
		var startIndex=1;
		var tempSQL=0;
		var paramCount=arraylen(arguments.configStruct.arrParam);
		var questionMarkPosition=0;
		var paramIndex=1;
		var paramDump=0;
		if(arguments.configStruct.dbtype NEQ "" and arguments.configStruct.dbtype NEQ "datasource"){
			queryStruct.dbtype=arguments.configStruct.dbtype;	
			structdelete(queryStruct, 'datasource');
		}else if(isBoolean(queryStruct.datasource)){
			variables.throwError("dbQuery.init({datasource:datasource}) must be set before running dbQuery.execute() by either using dbQuery.table() or db.datasource=""myDatasource"";");
		}
		queryStruct.name="db."&arguments.name;
		</cfscript>
		<cfif paramCount>
            <cfquery attributeCollection="#queryStruct#"><cfloop condition="#running#"><cfscript>
                questionMarkPosition=find("?", arguments.sql, startIndex);
                </cfscript><cfif questionMarkPosition EQ 0><cfscript>
				if(paramCount and paramIndex-1 GT paramCount){
					variables.throwError("db.execute failed: There were more question marks then parameters in the current sql statement.  You must use dbQuery.param() to specify parameters.  A literal question mark is not allowed.<br /><br />SQL Statement:<br />"&arguments.sql);
				}
				running=false;
				</cfscript><cfelse><cfset tempSQL=mid(arguments.sql, startIndex, questionMarkPosition-startIndex)>#preserveSingleQuotes(tempSQL)#<cfqueryparam attributeCollection="#arguments.configStruct.arrParam[paramIndex]#"><cfscript>
                startIndex=questionMarkPosition+1;
                paramIndex++;
                </cfscript></cfif></cfloop><cfscript>
				if(paramCount GT paramIndex-1){ 
					variables.throwErrorForTooManyParameters(arguments.configStruct);
				}
                tempSQL=mid(arguments.sql, startIndex, len(arguments.sql)-(startIndex-1));
                </cfscript>#preserveSingleQuotes(tempSQL)#</cfquery>
        <cfelse>
            <cfquery attributeCollection="#queryStruct#">#preserveSingleQuotes(arguments.sql)#</cfquery>
        </cfif>
        <cfscript>
		if(structkeyexists(db, arguments.name)){
			return db[arguments.name];
		}else{
			return true;
		}
		</cfscript>
    </cffunction>
    
    <cffunction name="throwErrorForTooManyParameters" access="private" output="no">
    	<cfargument name="configStruct" type="struct" required="yes">
    	<cfscript>
		var errorMessage="db.execute failed: There were more parameters then question marks in the current sql statement.  You must run db.execute() before building any additional sql statements with the same db object.  If you need to build multiple queries before running db.execute() or db.insert(), you must use a copy of db, such as db2=duplicate(db);<br /><br />Previous SQL Statement:<br />";
		savecontent variable="paramDump"{
			writedump(arguments.configStruct.arrParam);	
			if(arguments.configStruct.disableQueryLog EQ false and arraylen(arguments.configStruct.arrQueryLog) GT 1){
				errorMessage&='Previous SQL statement<br />'&arguments.configStruct.arrQueryLog[arraylen(arguments.configStruct.arrQueryLog)-1];
			}
		}
		variables.throwError(errorMessage&"<br />Current SQL Statement:<br />"&arguments.configStruct.arrQueryLog[arraylen(arguments.configStruct.arrQueryLog)]&"<br />Parameters:<br />"&paramDump);
		</cfscript>
	</cffunction>
    
    <cffunction name="newQuery" access="public">
    	<cfargument name="config" type="struct" required="no" default="#{}#">
        <cfscript>
		var queryCopy=duplicate(variables.cachedQueryObject);
		structappend(arguments.config, variables.config, false);
		arguments.config.dbQuery=queryCopy;
		arguments.config.parseSQLFunctionStruct=arguments.config.parseSQLFunctionStruct;
		queryCopy.init(this, arguments.config);
		return queryCopy;
		</cfscript>
	</cffunction>
    
    <cffunction name="insertAndReturnID" access="package" returntype="any" output="no" hint="Executes the insert statement and returns the inserted ID if insert was successful.">
    	<cfargument name="name" type="variablename" required="yes" hint="A variable name for the query result.  Helps to identify query when debugging.">
    	<cfargument name="configStruct" type="struct" required="yes">
        <cfscript>
		var db=0;
		var result=variables.execute(arguments.name, arguments.configStruct);
        var queryStruct={
			lazy=arguments.configStruct.lazy,
			datasource=arguments.configStruct.datasource,
			name:"db."&arguments.name&"_id"
		};
		</cfscript>
        <cfif result.success>
            <cfquery attributeCollection="#queryStruct#">
            #preserveSingleQuotes(arguments.configStruct.insertIDSQL)#
            </cfquery>
            <cfreturn {success:true, result:db[arguments.name&"_id"]}>
		<cfelse>
        	<cfreturn result>
		</cfif>
    </cffunction>
    
    <cffunction name="execute" access="package" returntype="struct" output="yes">
    	<cfargument name="name" type="variablename" required="yes" hint="A variable name for the query result.  Helps to identify query when debugging.">
    	<cfargument name="configStruct" type="struct" required="yes">
        <cfscript>
		if(not structkeyexists(arguments.configStruct, 'sql') or not len(arguments.configStruct.sql)){
			variables.throwError("The sql statement must be set before running db.execute();");
		}
		
		local.processedSQL=variables.processSQL(arguments.configStruct);
		if(arguments.configStruct.cacheEnabled and arguments.configStruct.cacheForSeconds and left(local.processedSQL, 7) EQ "SELECT "){
			local.tempCacheEnabled=true;
		}else{
			local.tempCacheEnabled=false;
		}
		if(local.tempCacheEnabled){
			local.nowDate=now();
			local.cacheResult=variables.checkQueryCache(arguments.configStruct, local.processedSQL, local.nowDate);
			if(local.cacheResult.success){
				return {success:true, result:local.cacheResult.result};
			}
		}
		try{
			local.result=variables.runQuery(arguments.configStruct, arguments.name, local.processedSQL);
		}catch(database errorStruct){
			arguments.configStruct.dbQuery.reset();
			if(left(trim(local.processedSQL), 7) EQ "INSERT "){
				return {success:false};
			}else{
				rethrow;
			}
		}
		arguments.configStruct.dbQuery.reset();
		if(isQuery(local.result)){
			if(local.tempCacheEnabled){
				variables.cacheStruct[local.cacheResult.hashCode]={date:local.nowDate, result:local.result};
			}
			return {success:true, result:local.result};
		}else{
            return {success:true, result: true};
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
        <cfargument name="configStruct" type="struct" required="yes">
        <cfscript>
        var sql=arguments.configStruct.sql;
		// strip trusted sql
        sql=rereplace(sql, variables.trustSQLString&".*?"&variables.trustSQLString, chr(9), "all");
		
		// detect string literals
        if(find("'", sql) NEQ 0 or find('"', sql) NEQ 0){
            variables.throwError("The SQL statement can't contain single or double quoted string literals when using the db component.  You must use dbQuery.param() to specify all values including constants.<br /><br />SQL Statement:<br />"&variables.getCleanSQL(arguments.configStruct.sql));	
        }
		// strip c style comments
        sql=replace(sql, chr(10), " ", "all");
        sql=replace(sql, chr(13), " ", "all");
        sql=replace(sql, chr(9), " ", "all");
        sql=replace(sql, "/*", chr(10), "all");
        sql=replace(sql, "*/", chr(13), "all");
        sql=replace(sql, "*", chr(9), "all");
        sql=rereplace(sql, chr(10)&"[^\*]*?"&chr(13), chr(9), "all");
		
		// strip table/db/field names
		if(arguments.configStruct.identifierQuoteCharacter NEQ "" and arguments.configStruct.identifierQuoteCharacter NEQ "'"){
        	sql=rereplace(sql, arguments.configStruct.identifierQuoteCharacter&"[^"&arguments.configStruct.identifierQuoteCharacter&"]*"&arguments.configStruct.identifierQuoteCharacter, chr(9), "all");
		}
		
		// strip words not beginning with a number
        sql=rereplace(sql, "[a-zA-Z_][a-zA-Z\._0-9]*", chr(9), "all");
        
		// detect any remaining numbers
		if(refind("[0-9]", sql) NEQ 0){
			variables.throwError("The SQL statement can't contain literal numbers when using the db component.  You must use dbQuery.param() to specify all values including constants.<br /><br />SQL Statement:<br />"&variables.getCleanSQL(arguments.configStruct.sql)); 	
        }
        return sql;
        </cfscript> 
    </cffunction>
    
    <cffunction name="parseSQL" access="private" output="no" returntype="any">
        <cfargument name="configStruct" type="struct" required="yes">
        <cfargument name="sqlString" type="string" required="yes">
        <cfargument name="defaultDatabaseName" type="string" required="yes">
        <cfscript>
        var local=structnew();
        var tempSQL=arguments.sqlString;
		local.ps=structnew();
        local.ps.arrError=arraynew(1);
        local.ps.arrTable=arraynew(1);
        tempSQL=replace(replace(replace(replace(replace(tempSQL,chr(10)," ","all"),chr(9)," ","all"),chr(13)," ","all"),")"," ) ","all"),"("," ( ","all");
        tempSQL=" "&rereplace(replace(replace(replace(lcase(tempSQL),"\\"," ","all"),"\'"," ","all"),'\"'," ","all"), "/\*.*?\*/"," ", "all")&" ";
        tempSQL=rereplace(tempSQL,"'[^']*?'","''","all");
        tempSQL=rereplace(tempSQL,'"[^"]*?"',"''","all");
        
        local.ps.wherePos=findnocase(" where ",tempSQL);
        local.ps.setPos=findnocase(" set ",tempSQL);
        local.ps.valuesPos=refindnocase("\)\s*values",tempSQL);
        local.ps.fromPos=findnocase(" from ",tempSQL);
        local.ps.selectPos=findnocase(" select ",tempSQL);
        local.ps.insertPos=findnocase(" insert ",tempSQL);
        local.ps.replacePos=findnocase(" replace ",tempSQL);
        local.ps.intoPos=findnocase(" into ",tempSQL);
        local.ps.limitPos=findnocase(" limit ",tempSQL);
        local.ps.groupByPos=findnocase(" group by ",tempSQL);
        local.ps.orderByPos=findnocase(" order by ",tempSQL);
        local.ps.havingPos=findnocase(" having ",tempSQL);
        local.ps.firstLeftJoinPos=findnocase(" left join ",tempSQL);
        local.ps.firstParenthesisPos=findnocase(" ( ",tempSQL);
        local.ps.firstWHEREPos=len(tempSQL);
        if(left(trim(tempSQL), 5) EQ "show "){
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
        local.ps.lastWHEREPos=len(tempSQL);
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
                local.ps.setStatement=mid(tempSQL, local.ps.setPos+5, local.ps.wherePos-(local.ps.setPos+5));
            }else{
                local.ps.setStatement=mid(tempSQL, local.ps.setPos+5, len(tempSQL)-(local.ps.setPos+5));
            }
        }
        if(local.ps.wherePos){
            local.ps.whereStatement=mid(tempSQL, local.ps.wherePos+6, local.ps.lastWHEREPos-(local.ps.wherePos+6));
        }else{
            local.ps.whereStatement="";
        }
        local.ps.arrLeftJoin=arraynew(1);
        local.matching=true;
        local.curPos=1;
        while(local.matching){
            local.t9=structnew();
            local.t9.leftJoinPos=findnocase(" left join ",tempSQL, local.curPos);
            if(local.t9.leftJoinPos EQ 0) break;
            local.t9.onPos=findnocase(" on ",tempSQL, local.t9.leftJoinPos+1);
            if(local.t9.onPos EQ 0 or local.t9.onPos GT local.ps.firstWHEREPos){
                local.t9.onPos=local.ps.firstWHEREPos;
            }
            local.t9.table=mid(tempSQL, local.t9.leftJoinPos+11, local.t9.onPos-(local.t9.leftJoinPos+11));
			if(arguments.configStruct.identifierQuoteCharacter NEQ ""){
				local.t9.table=trim(replace(local.t9.table, arguments.configStruct.identifierQuoteCharacter,"","all"));
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
			if(arguments.configStruct.enableTablePrefixing){
				if(findnocase(variables.tableSQLString,local.t9.table) EQ 0){
					arrayappend(local.ps.arrError, "All tables in queries must be generated with dbQuery.table(table, datasource); function. This table wasn't: "&local.t9.table);
				}else{
					local.t9.table=replacenocase(local.t9.table,variables.tableSQLString,"");
					local.t9.tableAlias=replacenocase(local.t9.tableAlias,variables.tableSQLString,"");
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
            local.ps.endOfFromPos=len(tempSQL);
        }
        
        if(local.ps.intoPos and (local.ps.selectPos EQ 0 or local.ps.selectPos GT local.ps.intoPos)){
            if(local.ps.setPos){
                local.t9=structnew();
                local.t9.type="into";
                local.t9.table=mid(tempSQL, local.ps.intoPos+5, local.ps.setPos-(local.ps.intoPos+5));
                local.t9.tableAlias=local.t9.table;
                arrayappend(local.ps.arrTable, local.t9);
            }else if(local.ps.firstParenthesisPos){
                local.t9=structnew();
                local.t9.type="into";
                local.t9.table=mid(tempSQL, local.ps.intoPos+5, local.ps.firstParenthesisPos-(local.ps.intoPos+5));
                local.t9.tableAlias=local.t9.table;
                arrayappend(local.ps.arrTable, local.t9);
            }else{
                if(local.ps.selectPos){
                    local.t9=structnew();
                    local.t9.type="into";
                    local.t9.table=mid(tempSQL, local.ps.intoPos+5, local.ps.selectPos-(local.ps.intoPos+5));
                    local.t9.tableAlias=local.t9.table;
                    arrayappend(local.ps.arrTable, local.t9);
                }
            }
        }
        if(local.ps.fromPos){
            
            local.c2=mid(tempSQL, local.ps.fromPos+5, local.ps.endOfFromPos-(local.ps.fromPos+5));
            
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
				if(arguments.configStruct.enableTablePrefixing){
					if(findnocase(variables.tableSQLString,local.t9.table) EQ 0){
						arrayappend(local.ps.arrError, "All tables in queries must be generated with dbQuery.table(table, datasource); function. This table wasn't: "&local.t9.table);
					}else{
						local.t9.table=replacenocase(local.t9.table,variables.tableSQLString,arguments.configStruct.identifierQuoteCharacter);
						local.t9.tableAlias=replacenocase(local.t9.tableAlias,variables.tableSQLString,arguments.configStruct.identifierQuoteCharacter);
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
                local.ps.arrLeftJoin[local.i2].onstatement=mid(tempSQL, local.ps.arrLeftJoin[local.i2].onPos+4, local.np-(local.ps.arrLeftJoin[local.i2].onPos+4));
            }
        }
        for(local.i2=1;local.i2 LTE arraylen(local.ps.arrTable);local.i2++){
			if(arguments.configStruct.identifierQuoteCharacter NEQ ""){
				local.ps.arrTable[local.i2].table=trim(replace(local.ps.arrTable[local.i2].table,arguments.configStruct.identifierQuoteCharacter,"","all"));
				local.ps.arrTable[local.i2].tableAlias=trim(replace(local.ps.arrTable[local.i2].tableAlias,arguments.configStruct.identifierQuoteCharacter,"","all"));
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
		for(local.i2 in arguments.configStruct.parseSQLFunctionStruct){
			local.s=arguments.configStruct.parseSQLFunctionStruct[local.i2];
			local.ps=local.s(local.ps);
		}
        if(arraylen(local.ps.arrError) NEQ 0){
			variables.throwError(arraytolist(local.ps.arrError, "<br />")&"<br /><br />SQL Statement<br />"&local.ps.sql);
        }
        return local.ps.sql;
        </cfscript>
    </cffunction> 
    
    <cffunction name="throwError" access="private" output="yes">
    	<cfargument name="message" type="string" required="yes">
    	<cfscript>
        throw("An error occured with a query that was built just prior to calling db.execute().<br />"&arguments.message, "database");
		</cfscript>
    </cffunction>
    
    
    </cfoutput>
</cfcomponent>