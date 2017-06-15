#!/bin/bash

# Configuration

. ./config.sh

echo "Setup sample JBoss A-MQ demo application: creating the application"
. ./setup-login.sh
echo "	--> Creating the authentication objects"
echo "		--> Create a keystore for the broker SERVER"
[ -f amq-server.ks ] || keytool -genkeypair -keystore amq-server.ks -storepass password -keyalg RSA -alias amq-server -dname "CN=${OPENSHIFT_PRIMARY_USER}" -keypass password || { echo "FAILED: could not find or create the server keystore" && exit 1; }
echo "	--> Export the broker SERVER certificate from the keystore"
[ -f amq-server.cert ] || keytool -export -alias amq-server -keystore amq-server.ks -storepass password -file amq-server.cert || { echo "FAILED: could not find or create the server certificate" && exit 1; }
echo "	--> Create the CLIENT keystore"
[ -f amq-client.ks ] || keytool -genkeypair -keystore amq-client.ks -storepass password -keyalg RSA -alias amq-client -dname "CN=${OPENSHIFT_PRIMARY_USER}" -keypass password || { echo "FAILED: could not find or create the client keystore" && exit 1; }
echo "	--> import the previous exported brokers certificate into a CLIENT truststore"
[ -f amq-client.ts ] || echo yes |  keytool -import -alias amq-server -keystore amq-client.ts -storepass password -file amq-server.cert || { echo "FAILED: could find or create the client truststore " && exit 1; }
echo "	--> If you want to make trusted also the client, you must export the clients certificate from the keystore"
[ -f amq-client.cert ] || keytool -export -alias amq-client -keystore amq-client.ks -storepass password -file amq-client.cert || { echo "FAILED" && exit 1; }
echo "	--> Import the clients exported certificate into a broker SERVER truststore"
echo yes | keytool -import -alias amq-client -keystore amq-server.ts -storepass password -file amq-client.cert || { echo "FAILED: could not import the client certificates into the server truststore " && exit 1; }
echo "	--> Verify the contents of the keystore"
[ "`keytool -list -keystore amq-server.ks -storepass password| grep amq-server | wc -l`" == 0 ] && echo "FAILED: could not verify the contents of the server  keystore" && exit 1
echo "	--> Verify the contents of the keystore"
[ "`keytool -list -keystore amq-client.ts -storepass password | grep amq-server | wc -l`" == 0 ] && echo "FAILED: could not verify the contents of the client truststore" && exit 1
echo "	--> Verify the contents of the keystore"
[ "`keytool -list -keystore amq-client.ks -storepass password |  grep amq-client | wc -l`" == 0 ] && echo "FAILED: could not verify the contents of the client keystore" && exit 1

echo "	--> Create a service account to be used for the A-MQ deployment"
[ "`oc get serviceaccounts | grep amq-service-account | wc -l `" == 0 ] && echo '{"kind": "ServiceAccount", "apiVersion": "v1", "metadata": {"name": "amq-service-account"}}' | oc create -f - || { echo "FAILED: could not configure the necessary security contexts" && exit 1; }
echo "	--> use the broker keyStore file to create the A-MQ secret"
oc get secret/amq-app-secret 2>/dev/null || oc secrets new amq-app-secret amq-server.ks amq-server.ts || { echo "FAILED: could not create the server secrets" && exit 1; }
echo "	--> Add the secret to the service account created earlier"
oc describe sa/amq-service-account || oc secrets add sa/amq-service-account secret/amq-app-secret || { echo "FAILED: could not add the server secrets to the openshift service account" && exit 1; }
echo "	--> Add the view role to the service account to enable viewing all the resources in the project namespace, which is necessary for managing the cluster when using the Kubernetes REST API agent for discovering the mesh endpoints"
[ "`oc describe policyBindings :default | grep -A5 'RoleBinding\[view\]' | grep amq-service-account | wc -l`" == 0 ] && oc policy add-role-to-user view system:serviceaccount:${OPENSHIFT_PRIMARY_PROJECT}:amq-service-account || { echo "FAILED" && exit 1; }
echo "	--> Create a new application from the amq62-persistent-ssl template"
[ "`oc get dc -l app=fuse-amq | wc -l`" == 0 ] && oc new-app amq62-persistent-ssl -l app=fuse-amq -p APPLICATION_NAME=${OPENSHIFT_APPLICATION_NAME} -p AMQ_MESH_DISCOVERY_TYPE=kube -p AMQ_SPLIT=false -p MQ_PROTOCOL=openwire -p MQ_QUEUES=testqueue -p MQ_USERNAME=admin -p MQ_PASSWORD=password -p MQ_TOPICS=testtopic -p AMQ_TRUSTSTORE=amq-server.ts -p AMQ_TRUSTSTORE_PASSWORD=password -p AMQ_KEYSTORE=amq-server.ks -p AMQ_KEYSTORE_PASSWORD=password -p AMQ_STORAGE_USAGE_LIMIT=256M || { echo "FAILED" && exit 1; }
echo "	--> Verify the application is working normally"
oc status || { echo "FAILED" && exit 1; }
echo "	--> Create a route to the frontend"
[ "`oc get route -l app=fuse-amq | wc -l`" == 0 ] &&  oc create route passthrough ${OPENSHIFT_APPLICATION_NAME} --service=${OPENSHIFT_APPLICATION_NAME}-amq-tcp-ssl || { echo "FAILED" && exit 1; }

echo "	--> MANUALLY CREATE an maven project using the camel-archetype-activemq archetype in JBoss Developer Studio using:"
echo "		--> Camel Context: "

cat > camel-context-fragment.xml << EOF_AMQ_CAMEL_CONTEXT
<bean id="activemq" class="org.apache.activemq.ActiveMQSslConnectionFactory">
	<property name="brokerURL"          value="failover://ssl://${OPENSHIFT_APPLICATION_NAME}-${OPENSHIFT_PRIMARY_PROJECT}.${OPENSHIFT_PRIMARY_APPS}:443" />
	<property name="userName"           value="admin" />
	<property name="password"           value="password" />
	<property name="trustStore"         value="$(pwd)/amq-client.ts" />
	<property name="trustStorePassword" value="password" />
	<property name="keyStore"           value="$(pwd)/amq-client.ks" />
	<property name="keyStorePassword"   value="password" />
</bean>
EOF_AMQ_CAMEL_CONTEXT
cat camel-context-fragment.xml
echo "	--> press enter to continue" && read
firefox https://master.rhsademo.net/console/java/jmx/attributes?con=broker-amq&main-tab=activemq&sub-tab=activemq-attributes&nid=root-org.apache.activemq-Broker-broker-amq-1-hm4pw-Queue
echo "Done"
