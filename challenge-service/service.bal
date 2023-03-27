import ballerina/http;
import wso2/data_model;
import ballerinax/mysql;
import ballerina/sql;
import ballerinax/mysql.driver as _;
import ballerina/io;
import ballerina/mime;
// import ballerina/file;
import ballerina/regex;
import ballerina/uuid;

configurable string USER = ?;
configurable string PASSWORD = ?;
configurable string HOST = ?;
configurable int PORT = ?;
configurable string DATABASE = ?;

type UpdatedChallenge record{
    string title;
    string description;
    string constraints;
    string difficulty;
};

# A service representing a network-accessible API
# bound to port `9096`.
@http:ServiceConfig {
    cors: {
        allowOrigins: ["http://www.m3.com", "http://www.hello.com", "https://localhost:3000"],
        allowCredentials: false,
        allowHeaders: ["CORELATION_ID"],
        exposeHeaders: ["X-CUSTOM-HEADER", "Authorization"],
        maxAge: 84900
    }
}
service /challengeService on new http:Listener(9096) {

    @http:ResourceConfig {
        cors: {
            allowOrigins: ["http://www.m3.com", "http://www.hello.com", "https://localhost:3000"],
            allowCredentials: true,
            allowHeaders: ["X-Content-Type-Options", "X-PINGOTHER", "Authorization"]
        }
    }
    resource function get challenge/[string challengeId]() returns data_model:Challenge|error? {
        data_model:Challenge challenge = check getChallenge(challengeId);
        return challenge;
    }

    @http:ResourceConfig {
        cors: {
            allowOrigins: ["http://www.m3.com", "http://www.hello.com", "https://localhost:3000"],
            allowCredentials: true,
            allowHeaders: ["X-Content-Type-Options", "X-PINGOTHER", "Authorization"]
        }
    }
    resource function get challenges/difficulty/[string difficulty]() returns data_model:Challenge[]?|error {
        
        data_model:Challenge[]|() challengesWithDifficulty = check getChallengesWithDifficulty(difficulty);
        return challengesWithDifficulty;
    }

    @http:ResourceConfig {
        cors: {
            allowOrigins: ["http://www.m3.com", "http://www.hello.com", "https://localhost:3000"],
            allowCredentials: true,
            allowHeaders: ["X-Content-Type-Options", "X-PINGOTHER", "Authorization"]
        }
    }
    resource function get challenges/template/[string challengeId] () returns byte[]|error{
        final mysql:Client dbClient = check new(host=HOST, user=USER, password=PASSWORD, port=PORT,database=DATABASE);

        byte[] testCaseFileBlob = check dbClient->queryRow(
            `SELECT challenge_template FROM challenge WHERE challenge_id = ${challengeId}`
        );
        check dbClient.close();
        return testCaseFileBlob;
    }


    @http:ResourceConfig {
        cors: {
            allowOrigins: ["http://www.m3.com", "http://www.hello.com", "https://localhost:3000"],
            allowCredentials: true,
            allowHeaders: ["X-Content-Type-Options", "X-PINGOTHER", "Authorization", "Content-Type"]
        }
    }
    resource function post challenge(http:Request request) returns string|int|error? {
        io:println("RECVD REQ");
        mime:Entity[] bodyParts = check request.getBodyParts();
        io:println(request.getContentType());

        data_model:Challenge newChallenge = {title: "", challengeId: "", description: "", difficulty: "HARD", testCase: [], template: [], constraints: ""};

        string fileName = "testCaseFile";
        string templateFileName = "templateFile";
        foreach mime:Entity item in bodyParts {
            // check if the body part is a zipped file or normal text
            io:print("content ytpy eis ...");
            io:println(item.getContentType());
            if item.getContentType().length() == 0  {
                string contentDispositionString = item.getContentDisposition().toString();
                // get the relevant key for the value provided
                string[] keyArray = regex:split(contentDispositionString, "name=\"");
                string key = regex:replaceAll(keyArray[1], "\"", "");
                newChallenge[key] = check item.getText();
            }
            // body part is a zipped file
            else {
                string contentDispositionString = item.getContentDisposition().toString();
                string[] keyArray = regex:split(contentDispositionString, "name=\"");
                string key = regex:replaceAll(keyArray[1], "\"", "");
                // Writes the incoming stream to a file using the `io:fileWriteBlocksFromStream` API
                // by providing the file location to which the content should be written.
                stream<byte[], io:Error?> streamer = check item.getByteStream();
                if key.equalsIgnoreCaseAscii("testCase") {
                    io:Error? fileWriteBlocksFromStream = io:fileWriteBlocksFromStream("/tmp/"+fileName+".zip", streamer);
                } else {
                    io:Error? fileWriteBlocksFromStream = io:fileWriteBlocksFromStream("/tmp/"+templateFileName+".zip", streamer);
                }
                
                check streamer.close();
                io:println("------");
            }

        }

        byte[] & readonly fileReadBytes = check io:fileReadBytes("/tmp/"+fileName+".zip");
        byte[] & readonly templateFileReadBytes = check io:fileReadBytes("/tmp/"+templateFileName+".zip");
        string|int? challengeId = check addChallenge(newChallenge, fileReadBytes, templateFileReadBytes, fileName, ".zip");
        return challengeId;

    }

    resource function put challenge/[string challengeId](http:Request request) returns UpdatedChallenge|string|error {

        json jsonPayload = check request.getJsonPayload();
        UpdatedChallenge updatedChallenge = check jsonPayload.cloneWithType(UpdatedChallenge);
        error? challenge = updateChallenge(challengeId, updatedChallenge);
        if challenge is error {
            if challenge.message().equalsIgnoreCaseAscii("INVALID CHALLENGE_ID.") {
                return "INVALID CHALLENGE_ID.";
            }
            return "DATABASE ERROR!";
        }
        updatedChallenge["challengeId"] = challengeId;
        return updatedChallenge;
    }

    resource function delete challenge/[string challengeId]() returns string {
        error? challenge = deleteChallenge(challengeId);
        if challenge is error {
            if challenge.message().equalsIgnoreCaseAscii("INVALID CHALLENGE_ID.") {
                return "INVALID CHALLENGE_ID.";
            }
            return "DATABASE ERROR!";
        }

        return "DELETE SUCCESSFULL";
    }

}

isolated function deleteChallenge(string challengeId) returns error?{
    final mysql:Client dbClient = check new(host=HOST, user=USER, password=PASSWORD, port=PORT,database=DATABASE);
    sql:ExecutionResult execRes = check dbClient->execute(`
        DELETE FROM challenge WHERE challenge_id = ${challengeId};
    `);
    if execRes.affectedRowCount == 0 {
        return error("INVALID CHALLENGE_ID.");
    }
    check dbClient.close();
    return;
}

isolated function updateChallenge(string challengeId, UpdatedChallenge updatedChallenge) returns error?{
    final mysql:Client dbClient = check new(host=HOST, user=USER, password=PASSWORD, port=PORT,database=DATABASE);
    sql:ExecutionResult execRes = check dbClient->execute(`
        UPDATE challenge SET title = ${updatedChallenge.title}, description = ${updatedChallenge.description}, constraints = ${updatedChallenge.constraints}, difficulty = ${updatedChallenge.difficulty} WHERE challenge_id = ${challengeId};
    `);
    if execRes.affectedRowCount == 0 {
        return error("INVALID CHALLENGE_ID.");
    }
    check dbClient.close();
    return;
}

isolated function addChallenge(data_model:Challenge newChallenge, byte[] testcaseFile, byte[] templateFile, string fileName, string fileExtension) returns string|int?|error {
    final mysql:Client dbClient = check new(host=HOST, user=USER, password=PASSWORD, port=PORT,database=DATABASE);
    string generatedChallengeId = "challenge-" + uuid:createType1AsString();

    sql:ExecutionResult execRes = check dbClient->execute(`
        INSERT INTO challenge (challenge_id, title, description, constraints, difficulty, testcase, challenge_template) VALUES (${generatedChallengeId},${newChallenge.title}, ${newChallenge.description}, ${newChallenge.constraints}, ${newChallenge.difficulty}, ${testcaseFile}, ${templateFile})
    `);
    check dbClient.close();
    return execRes.lastInsertId;
}

isolated function getChallenge(string challengeId) returns data_model:Challenge|sql:Error {
    final mysql:Client dbClient = check new(host=HOST, user=USER, password=PASSWORD, port=PORT,database=DATABASE);
    data_model:Challenge|sql:Error result = dbClient->queryRow(`SELECT * FROM challenge WHERE challenge_id = ${challengeId}`);
    check dbClient.close();
    return result;

}

isolated function getChallengesWithDifficulty(string difficulty) returns data_model:Challenge[]|sql:Error? {
    final mysql:Client dbClient = check new(host=HOST, user=USER, password=PASSWORD, port=PORT,database=DATABASE);
    stream<data_model:Challenge,sql:Error?> result = dbClient->query(`SELECT * FROM challenge WHERE difficulty = ${difficulty}`);
    check dbClient.close();

    data_model:Challenge[]|sql:Error? listOfChallenges = from data_model:Challenge challenge in result select challenge;

    return listOfChallenges;

}
