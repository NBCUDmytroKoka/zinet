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

#!/bin/bash

source ../bin/ini_parser.functions

echo "#### Parsing config file"
ini_parser ${1}
if [ $? -ne 0 ]; then
	echo "#### Error getting parsing config file"
	exit 1
fi

gziAdmin=billy
echo "#### Before parse: gziAdmin=${gziAdmin}"

echo "#### Setting up global variables"
ini_section_global
if [ $? -ne 0 ]; then
	echo "#### Error getting global variables"
	exit 1
fi

echo "#### After parse: gziAdmin=${gziAdmin}"

gziAdmin=bob

ini_update global gziAdmin

echo
echo "#### New file"
ini_writer 

