/**
 * Non-metric Space Library
 *
 * Authors: Bilegsaikhan Naidan (https://github.com/bileg), Leonid Boytsov (http://boytsov.info).
 * With contributions from Lawrence Cayton (http://lcayton.com/) and others.
 *
 * For the complete list of contributors and further details see:
 * https://github.com/searchivarius/NonMetricSpaceLib 
 * 
 * Copyright (c) 2015
 *
 * This code is released under the
 * Apache License Version 2.0 http://www.apache.org/licenses/.
 *
 */
#include <memory>
#include <iostream>
#include <sstream>
#include <stdexcept>

#include <thrift/protocol/TBinaryProtocol.h>
#include <thrift/transport/TSocket.h>
#include <thrift/transport/TTransportUtils.h>

#include "QueryService.h"

#include "ztimer.h"
#include "params_def.h"

#include <boost/program_options.hpp>



using std::string;
using std::exception;
using std::stringstream;
using std::cerr;
using std::cout;
using std::cin;
using std::endl;
using std::unique_ptr;

using namespace  ::similarity;

using namespace apache::thrift;
using namespace apache::thrift::protocol;
using namespace apache::thrift::transport;

namespace po = boost::program_options;

enum SearchType {
  kKNNSearch, kRangeSearch
};

static void Usage(const char *prog,
                  const po::options_description& desc) {
    std::cout << prog << std::endl
              << desc << std::endl;
}

void ParseCommandLineForClient(int argc, char*argv[],
                      string&                 host,
                      int&                    port,
                      SearchType&             searchType,
                      int&                    k,
                      double&                 r,
                      bool&                   retExternId,
                      bool&                   retObj,
                      string&                 queryTimeParams
                      ) {
  po::options_description ProgOptDesc("Allowed options");
  ProgOptDesc.add_options()
    (HELP_PARAM_OPT,    HELP_PARAM_MSG)
    (PORT_PARAM_OPT,    po::value<int>(&port)->required(), PORT_PARAM_MSG)
    (ADDR_PARAM_OPT,    po::value<string>(&host)->required(), ADDR_PARAM_MSG)
    (KNN_PARAM_OPT,     po::value<int>(&k), KNN_PARAM_MSG)
    (RANGE_PARAM_OPT,   po::value<double>(&r), RANGE_PARAM_MSG)
    (QUERY_TIME_PARAMS_PARAM_OPT, po::value<string>(&queryTimeParams)->default_value(""), QUERY_TIME_PARAMS_PARAM_MSG)
    (RET_EXT_ID_PARAM_OPT,   RET_EXT_ID_PARAM_MSG)
    (RET_OBJ_PARAM_OPT, RET_EXT_ID_PARAM_MSG)
    ;

  po::variables_map vm;
  try {
    po::store(po::parse_command_line(argc, argv, ProgOptDesc), vm);
    po::notify(vm);
  } catch (const exception& e) {
    Usage(argv[0], ProgOptDesc);
    cerr << e.what() << endl;
    exit(1);
  }

  if (vm.count("knn") == 1) {
    if (vm.count("range") != 0) {
      cerr << "Range search is not allowed if the KNN search is specified!";
      Usage(argv[0], ProgOptDesc);
      exit(1);
    }
    searchType = kKNNSearch;
  } else if (vm.count("range") == 1) {
    if (vm.count("knn") != 0) {
      cerr << "KNN search is not allowed if the range search is specified";
      Usage(argv[0], ProgOptDesc);
      exit(1);
    }
    searchType = kRangeSearch;
  } else {
    cerr << "One has to specify either range or KNN-search parameter";
    Usage(argv[0], ProgOptDesc);
    exit(1);
  }

  retExternId = vm.count("retExternId") != 0;

  retObj = vm.count("retObj") != 0;

  if (vm.count("help")  ) {
    Usage(argv[0], ProgOptDesc);
    exit(0);
  }
}

int main(int argc, char *argv[]) {
  string      host;
  int         port = 0;
  int         k;
  double      r;
  bool        retExternId;
  bool        retObj;
  SearchType  searchType;
  string      queryTimeParams;

  ParseCommandLineForClient(argc, argv,
                      host,
                      port,
                      searchType,
                      k, r,
                      retExternId,
                      retObj,
                      queryTimeParams);

  // Let's read the query from the input stream
  string        s;
  stringstream  ss;

  while (getline(cin, s)) {
    ss << s << endl;
  }

  string queryObjStr = ss.str();

  boost::shared_ptr<TTransport>   socket(new TSocket(host, port));
  boost::shared_ptr<TTransport>   transport(new TBufferedTransport(socket));
  boost::shared_ptr<TProtocol>    protocol(new TBinaryProtocol(transport));
  QueryServiceClient              client(protocol);

  try {
    transport->open();

    try {
      if (!queryTimeParams.empty()) {
        client.setQueryTimeParams(queryTimeParams);
      }

      ReplyEntryList res;

      WallClockTimer wtm;

      wtm.reset();

      if (kKNNSearch == searchType) {
        cout << "Running a " << k << "-NN query" << endl;;
        client.knnQuery(res, k, queryObjStr, retExternId, retObj);
      } else {
        cout << "Running a range query with radius = " << r << endl;
        client.rangeQuery(res, r, queryObjStr, retExternId, retObj);
      }

      wtm.split();

      cout << "Finished in: " << wtm.elapsed() / 1e3f << " ms" << endl;

      for (auto e: res) {
        cout << "id=" << e.id << " dist=" << e.dist << ( retExternId ? " externId=" + e.externId : string("")) << endl; 
        if (retObj) cout << e.obj << endl;
      }
    } catch (const QueryException& e) {
      cerr << "Query execution error: " << e.message << endl;
      exit(1);
    }

    transport->close(); // Close transport !!!
  } catch (const TException& tx) {
    cerr << "Connection error: " << tx.what() << endl;
    exit(1);
  }

  return 0;
}

