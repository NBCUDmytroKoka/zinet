#!/bin/bash

################################################
#	Copyright (c) 2015-18 zibernetics, Inc.
#
#	Licensed under the Apache License, Version 2.0 (the "License");
#	you may not use this file except in compliance with the License.
#	You may obtain a copy of the License at
#	
#	    http://www.apache.org/licenses/LICENSE-2.0
#	
#	Unless required by applicable law or agreed to in writing, software
#	distributed under the License is distributed on an "AS IS" BASIS,
#	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#	See the License for the specific language governing permissions and
#	limitations under the License.
#
################################################

source netrc_parser.functions

echo "ftp login: $(netrcGetLogin netrc ftp)"
echo "ftp password: $(netrcGetPasswd netrc ftp)"
echo "ftp account: $(netrcGetAccount netrc ftp)"
echo
echo "mine login: $(netrcGetLogin netrc mine)"
echo "mine password: $(netrcGetPasswd netrc mine)"
echo "mine account: $(netrcGetAccount netrc mine)"
echo
echo "yours login: $(netrcGetLogin netrc yours)"
echo "yours password: $(netrcGetPasswd netrc yours)"
echo "yours account: $(netrcGetAccount netrc yours)"

echo
echo "Getting machines local"
netrcGetMachines netrc

echo
echo "Getting machines local2"
netrcGetMachines netrc2

echo
echo "Testing empty logins"
echo "empty2 login: $(netrcGetLogin netrc)"
echo "empty2 password: $(netrcGetPasswd netrc)"
echo "empty2 account: $(netrcGetAccount netrc)"

echo
echo "Testing empty logins2"
echo "empty login: $(netrcGetLogin netrc2)"
echo "empty password: $(netrcGetPasswd netrc2)"
echo "empty account: $(netrcGetAccount netrc2)"

echo
echo "Getting machines sshldap"
netrcGetMachines $(netrc_z sshldap)

#echo
#echo "Creating netrc file in std dir: $(netrc)"

#echo
#echo "Creating netrc file in ziNet dir: $(netrc_z sshldap)"

#echo
#theFile=$(netrc_z sshldap)
#echo "sshldap login: $(netrcGetLogin ${theFile})"